import 'dart:io';

import '../../models/app_settings.dart';
import '../app_log.dart';
import 'bundled_platform_covers.dart';
import 'gallery_builder.dart';
import 'gallery_renderer.dart';
import 'known_hosts.dart';
import 'publish_credentials.dart';
import 'publish_plan.dart';
import 'publish_transport.dart';
import 'ssh_config.dart';
import 'rsync_transport.dart';
import 'sftp_transport.dart';

/// Why a transport was chosen, so the result line can say what carried the
/// publish and the log can say why the other one did not.
class TransportChoice {
  const TransportChoice({required this.transport, required this.reason});

  final PublishTransport transport;
  final String reason;
}

/// Renders the library and uploads it, in one step, the way the Publish
/// button asks for it.
class PublishService {
  const PublishService({
    required this.buildPath,
    this.builder = const GalleryBuilder(
      platformCovers: BundledPlatformCovers(),
    ),
    this.renderer = const GalleryRenderer(
      platformCovers: BundledPlatformCovers(),
      assets: BundledGalleryAssets(),
    ),
    this.planner = const PublishPlanner(),
    this.rsync = const RsyncTransport(),
    this.sftp = const SftpTransport(),
    this.credentials = const PublishCredentialResolver(),
    this.hostKeyStore,
    this.log = const SilentAppLog(),
  });

  /// Where the rendered pages live. Outside the library folder, so publishing
  /// never writes into the user's captures.
  final String buildPath;
  final GalleryBuilder builder;
  final GalleryRenderer renderer;
  final PublishPlanner planner;
  final RsyncTransport rsync;
  final SftpTransport sftp;

  /// Answers what a publish has to ask for before it starts, and what it
  /// signs in with once it does.
  final PublishCredentialResolver credentials;

  /// Remembers the host keys accepted on first use. Left null, SFTP takes the
  /// server's word for who it is.
  final HostKeyStore? hostKeyStore;
  final AppLog log;

  Future<PublishOutcome> publish({
    required String libraryPath,
    required PublishSettings settings,
    String? secret,
    PublishCancellation? cancellation,
    PublishProgressCallback? onProgress,
  }) async {
    final problem = validate(libraryPath: libraryPath, settings: settings);
    if (problem != null) {
      throw PublishException(problem);
    }

    final stop = cancellation ?? PublishCancellation();
    stop.throwIfCancelled();

    onProgress?.call(const PublishProgress(message: 'Reading the library…'));
    final root = await builder.build(
      libraryPath: libraryPath,
      siteTitle: settings.site.title.trim().isEmpty
          ? 'Gaming Memories'
          : settings.site.title.trim(),
      excluded: settings.excluded,
    );

    stop.throwIfCancelled();
    onProgress?.call(const PublishProgress(message: 'Rendering the gallery…'));
    final rendered = await renderer.render(
      root: root,
      buildPath: buildPath,
      site: settings.site,
    );
    log.info(
      'Rendered ${rendered.pages.length} gallery pages and '
      '${rendered.covers.length} platform covers, '
      '${rendered.written} files changed.',
      category: 'publish',
    );

    final plan = planner.plan(
      root: root,
      buildPath: buildPath,
      renderedFiles: rendered.files,
      excludedAlbums: settings.excluded,
    );

    stop.throwIfCancelled();
    final choice = await selectTransport(settings);
    final transport = choice.transport is SftpTransport
        ? SftpTransport(
            credentials: credentials,
            hostKeys: await _hostKeyVerifier(settings.target),
          )
        : choice.transport;
    log.info(
      'Publishing ${plan.files.length} files over ${choice.transport.name}: '
      '${choice.reason}',
      category: 'publish',
    );

    final outcome = await transport.upload(
      PublishRequest(
        plan: plan,
        target: settings.target,
        libraryPath: libraryPath,
        buildPath: buildPath,
        secret: secret,
        cancellation: stop,
      ),
      onProgress: onProgress,
    );

    log.info(
      outcome.stopped
          ? 'Publish stopped: ${outcome.describe()}.'
          : 'Publish finished: ${outcome.describe()}.',
      category: 'publish',
    );
    return outcome;
  }

  /// Picks the uploader. Under `auto` rsync wins when this machine has a
  /// capable one and the key can be used without the app typing anything,
  /// because it compares a large tree in far fewer round trips.
  Future<TransportChoice> selectTransport(PublishSettings settings) async {
    switch (settings.transport) {
      case PublishTransportKind.sftp:
        return TransportChoice(transport: sftp, reason: 'chosen in Settings');
      case PublishTransportKind.rsync:
        return TransportChoice(transport: rsync, reason: 'chosen in Settings');
      case PublishTransportKind.auto:
        break;
    }

    final blocked = await rsyncBlocker(settings);
    if (blocked != null) {
      return TransportChoice(transport: sftp, reason: blocked);
    }
    return TransportChoice(
      transport: rsync,
      reason: 'a usable rsync is on PATH',
    );
  }

  /// Why rsync cannot carry this publish, or null when it can.
  Future<String?> rsyncBlocker(PublishSettings settings) async {
    final target = settings.target;

    switch (target.credential) {
      case PublishCredentialKind.password:
        // rsync would have to type the password on a terminal this app does
        // not have; SFTP can hand it over directly.
        return 'the publish signs in with a password';
      case PublishCredentialKind.manualKey:
        final keyPath = target.keyPath.trim();
        // rsync splits its -e value on whitespace, so a key path holding a
        // space cannot be passed to ssh through it.
        if (keyPath.contains(RegExp(r'\s'))) {
          return 'the SSH key path contains a space';
        }
        if (await keyIsEncrypted(keyPath)) {
          return 'the SSH key needs a passphrase';
        }
      case PublishCredentialKind.automaticKey:
        // ssh reads the agent and ~/.ssh itself, so rsync only has to be
        // able to run without asking anything.
        if (await credentials.secretNeeded(target) != PublishSecretKind.none) {
          return 'the SSH key needs a passphrase';
        }
    }

    final version = await rsync.probe();
    if (version == null) {
      return 'rsync is not on PATH';
    }
    if (version.isOpenRsync) {
      return 'the rsync on PATH is openrsync, which cannot mirror safely';
    }
    if (!version.isUsable) {
      return 'rsync ${version.major}.${version.minor} is older than 3.0';
    }

    return null;
  }

  /// The first thing stopping a publish, phrased for the user. Null means the
  /// settings are complete enough to try.
  static String? validate({
    required String libraryPath,
    required PublishSettings settings,
  }) {
    if (!settings.enabled) {
      return 'Publishing is turned off. Turn it on in Settings › Publish.';
    }
    if (libraryPath.trim().isEmpty) {
      return 'Choose a library folder before publishing.';
    }
    if (settings.target.host.trim().isEmpty) {
      return 'The publish target needs a host.';
    }
    if (settings.target.username.trim().isEmpty) {
      return 'The publish target needs a user name.';
    }
    if (settings.target.remotePath.trim().isEmpty) {
      return 'The publish target needs a remote folder.';
    }
    if (settings.target.credential == PublishCredentialKind.manualKey &&
        settings.target.keyPath.trim().isEmpty) {
      return 'Choose the SSH key to publish with.';
    }
    return null;
  }

  /// Builds the verifier for one publish, reading whatever `known_hosts`
  /// files apply to this host so a key `ssh` already trusts is not treated as
  /// new.
  Future<HostKeyVerifier?> _hostKeyVerifier(
    PublishTargetSettings target,
  ) async {
    final store = hostKeyStore;
    if (store == null) {
      return null;
    }

    final home = credentials.homeDirectory ?? _userHome();
    final config = await SshConfig.load(
      path: credentials.configPath,
      homeDirectory: home,
    );
    final resolved = config.forHost(
      target.host.trim(),
      user: target.username.trim(),
    );
    final paths = resolved.userKnownHostsFiles.isNotEmpty
        ? resolved.userKnownHostsFiles
        : KnownHosts.defaultPaths(home);

    return HostKeyVerifier(
      store: store,
      knownHosts: await KnownHosts.load(paths),
    );
  }

  static String? _userHome() =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  /// What the app has to ask the user for before a publish can start.
  Future<PublishSecretKind> secretNeeded(PublishSettings settings) =>
      credentials.secretNeeded(settings.target);

  /// Whether a key file is passphrase-protected.
  static Future<bool> keyIsEncrypted(String keyPath) async {
    final path = keyPath.trim();
    if (path.isEmpty) {
      return false;
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        return false;
      }
      return isEncryptedKey(await file.readAsString());
    } on FileSystemException {
      return false;
    }
  }
}
