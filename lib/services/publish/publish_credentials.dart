import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../../models/app_settings.dart';
import 'publish_transport.dart';
import 'ssh_agent_client.dart';
import 'ssh_config.dart';

/// What the SSH client is handed to sign in with.
class PublishCredentials {
  const PublishCredentials({this.identities = const [], this.password});

  final List<SSHIdentity> identities;

  /// Answered to the server's password prompt, when there is one to answer.
  final String? password;

  bool get isEmpty => identities.isEmpty && password == null;
}

/// Works out what a publish signs in with, and what it has to ask the user for
/// first.
class PublishCredentialResolver {
  const PublishCredentialResolver({
    this.agent = const _DefaultAgent(),
    this.homeDirectory,
    this.configPath,
  });

  final SshAgentFactory agent;

  /// Where `~/.ssh/config` is, for a test that must not read the real one.
  final String? configPath;

  /// Left null, the user's home is read from the environment. Tests hand in
  /// their own so they never touch a real `~/.ssh`.
  final String? homeDirectory;

  /// The identity files OpenSSH tries when none is named, newest algorithm
  /// first. A publish that finds none of them says so rather than failing at
  /// the handshake.
  static const defaultKeyNames = ['id_ed25519', 'id_ecdsa', 'id_rsa', 'id_dsa'];

  /// What the app has to ask for before it can start. Answering it costs one
  /// look at the agent and at `~/.ssh`, so it runs before a publish rather
  /// than in the middle of one.
  Future<PublishSecretKind> secretNeeded(PublishTargetSettings target) async {
    switch (target.credential) {
      case PublishCredentialKind.password:
        return PublishSecretKind.password;
      case PublishCredentialKind.manualKey:
        final key = File(target.keyPath.trim());
        if (!await key.exists()) {
          return PublishSecretKind.none;
        }
        return await _isEncrypted(key)
            ? PublishSecretKind.passphrase
            : PublishSecretKind.none;
      case PublishCredentialKind.automaticKey:
        final config = await _configFor(target);
        // An agent already holds unlocked keys, so nothing has to be typed.
        if ((await _agentIdentities(config)).isNotEmpty) {
          return PublishSecretKind.none;
        }
        final keys = await _automaticKeys(config);
        if (keys.isEmpty) {
          return PublishSecretKind.none;
        }
        for (final key in keys) {
          if (!await _isEncrypted(key)) {
            return PublishSecretKind.none;
          }
        }
        return PublishSecretKind.passphrase;
    }
  }

  /// Resolves the credentials, with [secret] being whatever [secretNeeded]
  /// asked for.
  Future<PublishCredentials> resolve(
    PublishTargetSettings target, {
    String? secret,
  }) async {
    switch (target.credential) {
      case PublishCredentialKind.password:
        if (secret == null || secret.isEmpty) {
          throw PublishException(
            'A password is needed for ${target.username}@${target.host}.',
          );
        }
        return PublishCredentials(password: secret);

      case PublishCredentialKind.manualKey:
        final path = target.keyPath.trim();
        if (path.isEmpty) {
          throw const PublishException(
            'Choose the SSH key to publish with, or let Gaming Memories find '
            'one.',
          );
        }
        return PublishCredentials(
          identities: await _keyPairs(File(path), secret),
        );

      case PublishCredentialKind.automaticKey:
        final config = await _configFor(target);
        final identities = <SSHIdentity>[...await _agentIdentities(config)];
        for (final key in await _automaticKeys(config)) {
          // A key the passphrase does not open is skipped: another one in
          // ~/.ssh, or the agent, may still answer for this host.
          try {
            identities.addAll(await _keyPairs(key, secret));
          } on PublishException {
            continue;
          }
        }
        if (identities.isEmpty) {
          throw PublishException(
            'No SSH key was found for ${target.username}@${target.host}. '
            'Add one to your agent, name one with IdentityFile in '
            '~/.ssh/config, or choose a key file in Settings.',
          );
        }
        return PublishCredentials(identities: identities);
    }
  }

  Future<SshHostConfig> _configFor(PublishTargetSettings target) async {
    final config = await SshConfig.load(
      path: configPath,
      homeDirectory: homeDirectory ?? _home(),
    );
    return config.forHost(target.host.trim(), user: target.username.trim());
  }

  /// The agent `~/.ssh/config` names for this host, and otherwise whichever
  /// one `SSH_AUTH_SOCK` points at.
  ///
  /// The config comes first because that is where an agent is usually set up
  /// — 1Password, Secretive and gpg-agent all use `IdentityAgent` — and
  /// because a desktop app launched from Finder inherits no `SSH_AUTH_SOCK`
  /// from a shell at all.
  Future<List<SSHIdentity>> _agentIdentities(SshHostConfig config) {
    final socket = config.identityAgent;
    return agent.create(socketPath: socket).identities();
  }

  /// The keys an automatic publish offers: the ones the config names for this
  /// host first, then the usual defaults — unless the config said those named
  /// keys are the only ones to use.
  Future<List<File>> _automaticKeys(SshHostConfig config) async {
    final keys = <File>[];
    for (final path in config.identityFiles) {
      final key = File(path);
      if (await key.exists()) {
        keys.add(key);
      }
    }
    if (config.identitiesOnly && keys.isNotEmpty) {
      return keys;
    }
    for (final key in await _defaultKeys()) {
      if (!keys.any((existing) => existing.path == key.path)) {
        keys.add(key);
      }
    }
    return keys;
  }

  /// The default identity files that are actually there, in OpenSSH's order.
  Future<List<File>> _defaultKeys() async {
    final home = homeDirectory ?? _home();
    if (home == null || home.isEmpty) {
      return const [];
    }

    final found = <File>[];
    for (final name in defaultKeyNames) {
      final key = File(p.join(home, '.ssh', name));
      if (await key.exists()) {
        found.add(key);
      }
    }
    return found;
  }

  static String? _home() =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  Future<bool> _isEncrypted(File key) async {
    try {
      return isEncryptedKey(await key.readAsString());
    } on FileSystemException {
      return false;
    }
  }

  Future<List<SSHKeyPair>> _keyPairs(File key, String? passphrase) async {
    if (!await key.exists()) {
      throw PublishException('The SSH key ${key.path} was not found.');
    }

    final String pem;
    try {
      pem = await key.readAsString();
    } on FileSystemException catch (error) {
      throw PublishException(
        'The SSH key ${key.path} could not be read.',
        detail: error.message,
      );
    }

    if (isEncryptedKey(pem) && (passphrase == null || passphrase.isEmpty)) {
      throw PublishException('The SSH key ${key.path} needs a passphrase.');
    }

    try {
      return SSHKeyPair.fromPem(pem, passphrase);
    } catch (error) {
      throw PublishException(
        'The SSH key ${key.path} could not be opened. Check the passphrase.',
        detail: '$error',
      );
    }
  }
}

/// Whether a key file's contents are passphrase-protected. Something that is
/// not a key at all reads as plain, so the failure is reported when it is used
/// rather than guessed at here.
bool isEncryptedKey(String pem) {
  try {
    return SSHKeyPair.isEncryptedPem(pem);
  } catch (_) {
    return false;
  }
}

/// Hands out agent clients, so a test can supply one that holds nothing
/// without reaching for the machine's own agent.
abstract interface class SshAgentFactory {
  /// [socketPath] is the agent `~/.ssh/config` named, when it named one.
  SshAgentClient create({String? socketPath});
}

class _DefaultAgent implements SshAgentFactory {
  const _DefaultAgent();

  @override
  SshAgentClient create({String? socketPath}) =>
      SshAgentClient(socketPath: socketPath);
}
