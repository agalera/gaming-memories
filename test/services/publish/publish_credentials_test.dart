import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/publish/publish_credentials.dart';
import 'package:gaming_memories/services/publish/publish_transport.dart';
import 'package:gaming_memories/services/publish/ssh_agent_client.dart';
import 'package:path/path.dart' as p;

/// An agent that holds whatever a test says it does, without a socket.
class FakeAgent implements SshAgentFactory {
  FakeAgent({this.identities = const []});

  final List<SSHIdentity> identities;

  /// Every socket path the resolver asked for, so a test can prove the one
  /// from ~/.ssh/config was used.
  final List<String?> sockets = [];

  @override
  SshAgentClient create({String? socketPath}) {
    sockets.add(socketPath);
    return _FakeAgentClient(identities);
  }
}

class _FakeAgentClient implements SshAgentClient {
  _FakeAgentClient(this._identities);

  final List<SSHIdentity> _identities;

  @override
  String? get socketPath => _identities.isEmpty ? null : '/fake/agent';

  @override
  String? get resolvedSocketPath => socketPath;

  @override
  bool get isAvailable => _identities.isNotEmpty;

  @override
  Future<List<SSHIdentity>> identities() async => _identities;
}

SSHIdentity fakeIdentity(String comment) => SSHIdentity.custom(
  type: 'ssh-ed25519',
  publicKey: SSHRawHostKey(Uint8List.fromList(utf8.encode('key'))),
  comment: comment,
  signer: (_) => SSHRawSignature(Uint8List(0)),
);

/// Makes a real key with ssh-keygen, so the resolver is exercised against
/// something that actually parses. Nothing secret is committed: every key
/// lives in a temporary folder for the length of one test.
Future<String?> generateKey(String path, {String passphrase = ''}) async {
  try {
    final result = await Process.run('ssh-keygen', [
      '-t',
      'ed25519',
      '-N',
      passphrase,
      '-C',
      'gaming-memories-test',
      '-f',
      path,
      '-q',
    ]);
    return result.exitCode == 0 ? path : null;
  } on ProcessException {
    return null;
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('publish-credentials');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  /// Puts a real key at `~/.ssh/<name>`, or skips the test when this machine
  /// has no ssh-keygen to make one with.
  Future<String> writeKey(String name, {String passphrase = ''}) async {
    final directory = Directory(p.join(root.path, '.ssh'));
    await directory.create(recursive: true);
    final path = await generateKey(
      p.join(directory.path, name),
      passphrase: passphrase,
    );
    if (path == null) {
      markTestSkipped('ssh-keygen is not on PATH, so no key can be made.');
      fail('skipped');
    }
    return path;
  }

  PublishCredentialResolver resolver({FakeAgent? agent}) {
    return PublishCredentialResolver(
      agent: agent ?? FakeAgent(),
      homeDirectory: root.path,
      configPath: p.join(root.path, '.ssh', 'config'),
    );
  }

  Future<void> writeConfig(String contents) async {
    final file = File(p.join(root.path, '.ssh', 'config'));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  PublishTargetSettings target(
    PublishCredentialKind credential, {
    String keyPath = '',
  }) {
    return PublishTargetSettings(
      host: 'example.com',
      port: 22,
      username: 'deploy',
      remotePath: '/srv/site',
      credential: credential,
      keyPath: keyPath,
      fileMode: '644',
      directoryMode: '755',
      deleteRemoved: true,
    );
  }

  group('what has to be asked for', () {
    test('a password is always asked for', () async {
      expect(
        await resolver().secretNeeded(target(PublishCredentialKind.password)),
        PublishSecretKind.password,
      );
    });

    test('an agent that holds a key asks for nothing', () async {
      await writeKey('id_ed25519', passphrase: 'letmein');
      final agent = FakeAgent(identities: [fakeIdentity('me@laptop')]);

      expect(
        await resolver(agent: agent)
            .secretNeeded(target(PublishCredentialKind.automaticKey)),
        PublishSecretKind.none,
      );
    });

    test('an encrypted key and no agent asks for the passphrase', () async {
      await writeKey('id_ed25519', passphrase: 'letmein');

      expect(
        await resolver().secretNeeded(
          target(PublishCredentialKind.automaticKey),
        ),
        PublishSecretKind.passphrase,
      );
    });

    test('one unprotected key among several asks for nothing', () async {
      await writeKey('id_ed25519', passphrase: 'letmein');
      await writeKey('id_rsa');

      expect(
        await resolver().secretNeeded(
          target(PublishCredentialKind.automaticKey),
        ),
        PublishSecretKind.none,
      );
    });

    test('no key at all asks for nothing, and fails when used', () async {
      expect(
        await resolver().secretNeeded(
          target(PublishCredentialKind.automaticKey),
        ),
        PublishSecretKind.none,
      );
    });

    test('a chosen key is asked about on its own', () async {
      final encrypted = await writeKey('deploy', passphrase: 'letmein');
      final plain = await writeKey('other');

      expect(
        await resolver().secretNeeded(
          target(PublishCredentialKind.manualKey, keyPath: encrypted),
        ),
        PublishSecretKind.passphrase,
      );
      expect(
        await resolver().secretNeeded(
          target(PublishCredentialKind.manualKey, keyPath: plain),
        ),
        PublishSecretKind.none,
      );
    });
  });

  group('resolving', () {
    test('a password becomes the password the client answers with', () async {
      final signIn = await resolver().resolve(
        target(PublishCredentialKind.password),
        secret: 'hunter2',
      );

      expect(signIn.password, 'hunter2');
      expect(signIn.identities, isEmpty);
    });

    test('a password that was never given is refused', () async {
      expect(
        () => resolver().resolve(target(PublishCredentialKind.password)),
        throwsA(isA<PublishException>()),
      );
    });

    test('a chosen key is the only one used', () async {
      final path = await writeKey('deploy');
      await writeKey('id_ed25519');

      final signIn = await resolver().resolve(
        target(PublishCredentialKind.manualKey, keyPath: path),
      );

      expect(signIn.identities, hasLength(1));
      expect(signIn.password, isNull);
    });

    test('a chosen key with no path names the setting to fix', () async {
      expect(
        () => resolver().resolve(target(PublishCredentialKind.manualKey)),
        throwsA(
          isA<PublishException>().having(
            (error) => error.message,
            'message',
            contains('Choose the SSH key'),
          ),
        ),
      );
    });

    test('automatic takes the agent and the default keys together', () async {
      await writeKey('id_ed25519');
      final agent = FakeAgent(identities: [fakeIdentity('me@laptop')]);

      final signIn = await resolver(agent: agent)
          .resolve(target(PublishCredentialKind.automaticKey));

      expect(signIn.identities, hasLength(2));
    });

    test('automatic skips a key the passphrase does not open', () async {
      await writeKey('id_ed25519', passphrase: 'letmein');
      await writeKey('id_rsa');

      final signIn = await resolver().resolve(
        target(PublishCredentialKind.automaticKey),
      );

      expect(signIn.identities, hasLength(1));
    });

    test('automatic with nothing to offer says where to look', () async {
      expect(
        () => resolver().resolve(target(PublishCredentialKind.automaticKey)),
        throwsA(
          isA<PublishException>().having(
            (error) => error.message,
            'message',
            allOf(contains('No SSH key'), contains('agent')),
          ),
        ),
      );
    });

    test('the default keys are tried in OpenSSH order', () {
      expect(PublishCredentialResolver.defaultKeyNames, [
        'id_ed25519',
        'id_ecdsa',
        'id_rsa',
        'id_dsa',
      ]);
    });
  });

  test('isEncryptedKey reads a real key either way', () async {
    final plain = await writeKey('plain');
    final sealed = await writeKey('sealed', passphrase: 'letmein');

    expect(isEncryptedKey(await File(plain).readAsString()), isFalse);
    expect(isEncryptedKey(await File(sealed).readAsString()), isTrue);
    expect(isEncryptedKey('not a key'), isFalse);
    expect(isEncryptedKey(''), isFalse);
  });
  group('~/.ssh/config', () {
    test('the agent it names is the one asked, not SSH_AUTH_SOCK', () async {
      await writeConfig(
        'Host example.com\n  IdentityAgent /tmp/from-config.sock\n',
      );
      final agent = FakeAgent(identities: [fakeIdentity('me@laptop')]);

      final signIn = await resolver(agent: agent)
          .resolve(target(PublishCredentialKind.automaticKey));

      // An agent set up this way is the normal case — 1Password, Secretive
      // and gpg-agent all do it — and a windowed app inherits no
      // SSH_AUTH_SOCK from a shell anyway.
      expect(agent.sockets, ['/tmp/from-config.sock']);
      expect(signIn.identities, hasLength(1));
    });

    test('no IdentityAgent falls back to the environment', () async {
      await writeConfig('Host example.com\n  User deploy\n');
      final agent = FakeAgent(identities: [fakeIdentity('me@laptop')]);

      await resolver(agent: agent)
          .resolve(target(PublishCredentialKind.automaticKey));

      expect(agent.sockets, [null]);
    });

    test('an agent it names means nothing has to be typed', () async {
      await writeKey('id_ed25519', passphrase: 'letmein');
      await writeConfig('Host *\n  IdentityAgent /tmp/from-config.sock\n');
      final agent = FakeAgent(identities: [fakeIdentity('me@laptop')]);

      expect(
        await resolver(agent: agent)
            .secretNeeded(target(PublishCredentialKind.automaticKey)),
        PublishSecretKind.none,
      );
      expect(agent.sockets, ['/tmp/from-config.sock']);
    });

    test('a key it names for the host is used', () async {
      final named = await writeKey('deploy-key');
      await writeConfig('Host example.com\n  IdentityFile $named\n');

      final signIn = await resolver().resolve(
        target(PublishCredentialKind.automaticKey),
      );

      expect(signIn.identities, hasLength(1));
    });

    test('a named key comes before the default ones', () async {
      final named = await writeKey('deploy-key');
      await writeKey('id_ed25519');
      await writeConfig('Host example.com\n  IdentityFile $named\n');

      final signIn = await resolver().resolve(
        target(PublishCredentialKind.automaticKey),
      );

      expect(signIn.identities, hasLength(2));
    });

    test('IdentitiesOnly keeps the default keys out', () async {
      final named = await writeKey('deploy-key');
      await writeKey('id_ed25519');
      await writeConfig(
        'Host example.com\n  IdentityFile $named\n  IdentitiesOnly yes\n',
      );

      final signIn = await resolver().resolve(
        target(PublishCredentialKind.automaticKey),
      );

      expect(signIn.identities, hasLength(1));
    });

    test('a key named for another host is left alone', () async {
      final named = await writeKey('deploy-key');
      await writeConfig(
        'Host somewhere.else\n  IdentityFile $named\n  IdentitiesOnly yes\n',
      );

      expect(
        () => resolver().resolve(target(PublishCredentialKind.automaticKey)),
        throwsA(isA<PublishException>()),
      );
    });

    test('a chosen key ignores the config entirely', () async {
      final chosen = await writeKey('chosen');
      final other = await writeKey('id_ed25519');
      await writeConfig(
        'Host example.com\n'
        '  IdentityAgent /tmp/from-config.sock\n'
        '  IdentityFile $other\n',
      );
      final agent = FakeAgent(identities: [fakeIdentity('me@laptop')]);

      final signIn = await resolver(agent: agent)
          .resolve(target(PublishCredentialKind.manualKey, keyPath: chosen));

      expect(signIn.identities, hasLength(1));
      expect(agent.sockets, isEmpty);
    });
  });
}
