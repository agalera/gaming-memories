import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/controllers/library_controller.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/app_log.dart';
import 'package:gaming_memories/services/config_store.dart';
import 'package:gaming_memories/services/library_scanner.dart';
import 'package:gaming_memories/services/publish/publish_credentials.dart';
import 'package:gaming_memories/services/publish/publish_service.dart';
import 'package:gaming_memories/services/publish/publish_transport.dart';
import 'package:gaming_memories/services/publish/rsync_transport.dart';
import 'package:gaming_memories/services/publish/sftp_transport.dart';
import 'package:gaming_memories/services/publish/ssh_agent_client.dart';
import 'package:path/path.dart' as p;

/// Stands in for a transport so a publish can be driven end to end without a
/// server.
class _RecordingTransport implements PublishTransport {
  _RecordingTransport({this.failure});

  final PublishException? failure;
  PublishRequest? request;

  @override
  String get name => 'recording';

  @override
  Future<PublishOutcome> upload(
    PublishRequest request, {
    PublishProgressCallback? onProgress,
  }) async {
    this.request = request;
    final problem = failure;
    if (problem != null) {
      throw problem;
    }
    onProgress?.call(const PublishProgress(message: 'Uploading…', value: 0.5));
    return const PublishOutcome(
      uploaded: 3,
      skipped: 1,
      deleted: 2,
      bytes: 100,
    );
  }
}

/// A service whose transport choice is fixed, so the controller can be tested
/// without rsync or a network.
class _StubbedPublishService extends PublishService {
  _StubbedPublishService({required super.buildPath, required this.transport});

  final PublishTransport transport;

  @override
  Future<TransportChoice> selectTransport(
    PublishSettings settings, {
    String? passphrase,
  }) async {
    return TransportChoice(transport: transport, reason: 'stubbed');
  }
}

/// Holds nothing, so a test never reaches the machine's own SSH agent.
class _EmptyAgent implements SshAgentFactory {
  const _EmptyAgent();

  @override
  SshAgentClient create({String? socketPath}) => SshAgentClient(socketPath: '');
}

void main() {
  late Directory root;
  late Directory library;
  late Directory build;
  late ConfigStore store;

  /// Resolves against an empty agent and an empty home, so nothing a test
  /// asks depends on the machine it runs on.
  late PublishCredentialResolver emptyResolver;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gaming-memories-publish-');
    emptyResolver = PublishCredentialResolver(
      agent: const _EmptyAgent(),
      homeDirectory: p.join(root.path, 'home'),
    );
    library = Directory(p.join(root.path, 'library'));
    build = Directory(p.join(root.path, 'publish'));
    await library.create(recursive: true);
    store = ConfigStore(filePath: p.join(root.path, 'settings.json'));
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<void> capture(String relativePath) async {
    final file = File(p.join(library.path, p.joinAll(relativePath.split('/'))));
    await file.parent.create(recursive: true);
    await file.writeAsString('image');
  }

  PublishSettings settingsWith({
    bool enabled = true,
    PublishCredentialKind credential = PublishCredentialKind.automaticKey,
    String keyPath = '',
    List<String> excluded = const [],
  }) {
    return PublishSettings(
      enabled: enabled,
      site: const PublishSiteSettings(
        title: 'Games Screenshots',
        author: '@fmartingr',
        url: 'https://screenshots.example.com',
        footerText: 'Spoilers ahead',
      ),
      target: PublishTargetSettings(
        host: 'example.com',
        port: 22,
        username: 'deploy',
        remotePath: '/srv/site',
        credential: credential,
        keyPath: keyPath,
        fileMode: '644',
        directoryMode: '755',
        deleteRemoved: true,
      ),
      excluded: excluded,
    );
  }

  Future<LibraryController> controllerWith({
    required PublishSettings publish,
    PublishService? service,
  }) async {
    await store.save(AppSettings(outputPath: library.path, publish: publish));
    final controller = LibraryController(
      configStore: store,
      scanner: const LibraryScanner(),
      sources: const [],
      publishService: service,
    );
    await controller.initialize();
    return controller;
  }

  test('the Publish button only appears once publishing is on', () async {
    final off = await controllerWith(
      publish: settingsWith(enabled: false),
      service: PublishService(buildPath: build.path),
    );
    expect(off.canPublish, isFalse);

    final on = await controllerWith(
      publish: settingsWith(keyPath: '/key'),
      service: PublishService(buildPath: build.path),
    );
    expect(on.canPublish, isTrue);
  });

  test('a build without a publish service offers no button', () async {
    final controller = await controllerWith(publish: settingsWith());

    expect(controller.canPublish, isFalse);
  });

  test('renders and uploads, then reports what happened', () async {
    await capture('Steam/Hades/a.png');
    final transport = _RecordingTransport();
    final controller = await controllerWith(
      publish: settingsWith(keyPath: '/key'),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: transport,
      ),
    );

    await controller.publish();

    expect(controller.isPublishing, isFalse);
    expect(controller.notificationKind, NotificationKind.success);
    expect(controller.message, contains('example.com'));
    expect(controller.message, contains('3 uploaded'));
    expect(controller.message, contains('1 unchanged'));
    expect(controller.message, contains('2 removed'));

    final page = File(p.join(build.path, 'Steam', 'Hades', 'index.html'));
    expect(await page.exists(), isTrue);
    expect(await page.readAsString(), contains('Games Screenshots'));

    // The library holds captures, never pages.
    expect(
      await File(p.join(library.path, 'Steam', 'Hades', 'index.html')).exists(),
      isFalse,
    );

    final plan = transport.request!.plan;
    expect(plan.remotePaths, contains('Steam/Hades/a.png'));
    expect(plan.remotePaths, contains('Steam/Hades/index.html'));
  });

  test('an excluded album reaches the transport as an exclusion', () async {
    await capture('Steam/Hades/a.png');
    await capture('Steam/Private/b.png');
    final transport = _RecordingTransport();
    final controller = await controllerWith(
      publish: settingsWith(keyPath: '/key', excluded: ['Steam/Private']),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: transport,
      ),
    );

    await controller.publish();

    final plan = transport.request!.plan;
    expect(plan.remotePaths, isNot(contains('Steam/Private/b.png')));
    expect(plan.excludedAlbums, ['Steam/Private']);
  });

  test('an automatic key is enough; no key has to be chosen', () async {
    await capture('Steam/Hades/a.png');
    final transport = _RecordingTransport();
    final controller = await controllerWith(
      publish: settingsWith(),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: transport,
      ),
    );

    await controller.publish();

    expect(controller.notificationKind, NotificationKind.success);
    expect(transport.request, isNotNull);
  });

  test('refuses with a usable message when the target is incomplete', () async {
    final transport = _RecordingTransport();
    final controller = await controllerWith(
      publish: PublishSettings(
        enabled: true,
        target: const PublishTargetSettings.defaults().copyWith(
          host: 'example.com',
          username: 'deploy',
        ),
      ),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: transport,
      ),
    );

    await controller.publish();

    expect(controller.notificationKind, NotificationKind.warning);
    expect(controller.message, contains('remote folder'));
    expect(transport.request, isNull);
  });

  test('a key file with no path chosen is refused', () async {
    final transport = _RecordingTransport();
    final controller = await controllerWith(
      publish: settingsWith(credential: PublishCredentialKind.manualKey),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: transport,
      ),
    );

    await controller.publish();

    expect(controller.notificationKind, NotificationKind.warning);
    expect(controller.message, contains('SSH key'));
    expect(transport.request, isNull);
  });

  test('reports a transport failure without a stack trace', () async {
    await capture('Steam/Hades/a.png');
    final controller = await controllerWith(
      publish: settingsWith(keyPath: '/key'),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: _RecordingTransport(
          failure: const PublishException(
            'The server refused the key for deploy.',
            detail: 'permission denied',
          ),
        ),
      ),
    );

    await controller.publish();

    expect(controller.notificationKind, NotificationKind.error);
    expect(controller.error, contains('refused the key'));
    expect(controller.error, contains('permission denied'));
    expect(controller.isPublishing, isFalse);
  });

  test('asks nothing for a key file without a passphrase', () async {
    final plain = File(p.join(root.path, 'plain-key'));
    await plain.writeAsString('not a key');

    final controller = await controllerWith(
      publish: settingsWith(
        credential: PublishCredentialKind.manualKey,
        keyPath: plain.path,
      ),
      service: PublishService(
        buildPath: build.path,
        credentials: emptyResolver,
      ),
    );

    expect(await controller.publishSecretNeeded(), PublishSecretKind.none);
  });

  test('asks for the password when the publish signs in with one', () async {
    final controller = await controllerWith(
      publish: settingsWith(credential: PublishCredentialKind.password),
      service: PublishService(
        buildPath: build.path,
        credentials: emptyResolver,
      ),
    );

    expect(await controller.publishSecretNeeded(), PublishSecretKind.password);
  });

  test('asks nothing again once a secret is given', () async {
    await capture('Steam/Hades/a.png');
    final controller = await controllerWith(
      publish: settingsWith(credential: PublishCredentialKind.password),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: _RecordingTransport(),
      ),
    );

    expect(await controller.publishSecretNeeded(), PublishSecretKind.password);
    await controller.publish(secret: 'hunter2');
    expect(await controller.publishSecretNeeded(), PublishSecretKind.none);
  });

  test('the secret reaches the transport', () async {
    await capture('Steam/Hades/a.png');
    final transport = _RecordingTransport();
    final controller = await controllerWith(
      publish: settingsWith(credential: PublishCredentialKind.password),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: transport,
      ),
    );

    await controller.publish(secret: 'hunter2');

    expect(transport.request!.secret, 'hunter2');
  });

  test('a failed publish does not reuse the secret that failed', () async {
    await capture('Steam/Hades/a.png');
    final controller = await controllerWith(
      publish: settingsWith(credential: PublishCredentialKind.password),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: _RecordingTransport(
          failure: const PublishException('The server refused the password.'),
        ),
      ),
    );

    await controller.publish(secret: 'wrong');

    expect(await controller.publishSecretNeeded(), PublishSecretKind.password);
  });

  test('changing the destination asks for the secret again', () async {
    await capture('Steam/Hades/a.png');
    final controller = await controllerWith(
      publish: settingsWith(credential: PublishCredentialKind.password),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: _RecordingTransport(),
      ),
    );
    await controller.publish(secret: 'hunter2');
    expect(await controller.publishSecretNeeded(), PublishSecretKind.none);

    await controller.updateSettings(
      controller.settings.copyWith(
        publish: controller.settings.publish.copyWith(
          target: controller.settings.publish.target.copyWith(
            host: 'elsewhere.example.com',
          ),
        ),
      ),
      showNotification: false,
    );

    expect(await controller.publishSecretNeeded(), PublishSecretKind.password);
  });

  test('keeps the passphrase out of the log', () async {
    await capture('Steam/Hades/a.png');
    final log = _CapturingLog();
    await store.save(
      AppSettings(
        outputPath: library.path,
        publish: settingsWith(keyPath: '/key'),
      ),
    );
    final controller = LibraryController(
      configStore: store,
      scanner: const LibraryScanner(),
      sources: const [],
      log: log,
      publishService: _StubbedPublishService(
        buildPath: build.path,
        transport: _RecordingTransport(),
      ),
    );
    await controller.initialize();

    await controller.publish(secret: 'hunter2');
    log.info('Tried with hunter2.', category: 'publish');

    expect(log.lines.join('\n'), isNot(contains('hunter2')));
    expect(log.lines.join('\n'), contains('<REDACTED>'));
  });

  test('a real transport is picked when none is stubbed', () async {
    final service = PublishService(
      buildPath: build.path,
      credentials: emptyResolver,
    );
    final choice = await service.selectTransport(
      settingsWith(keyPath: '/key')
          .copyWith(transport: PublishTransportKind.sftp),
    );

    expect(choice.transport, isA<SftpTransport>());

    final forced = await service.selectTransport(
      settingsWith(keyPath: '/key')
          .copyWith(transport: PublishTransportKind.rsync),
    );
    expect(forced.transport, isA<RsyncTransport>());
  });
  test('a stop is reported as what happened, not as a failure', () async {
    await capture('Steam/Hades/a.png');
    final transport = _StoppingTransport();
    final controller = await controllerWith(
      publish: settingsWith(),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: transport,
      ),
    );

    await controller.publish();

    expect(controller.notificationKind, NotificationKind.warning);
    expect(controller.error, isNull);
    expect(controller.message, contains('stopped'));
    expect(controller.message, contains('2 uploaded'));
    expect(controller.isPublishing, isFalse);
  });

  test('the toast reports what the publish is on, and its progress', () async {
    await capture('Steam/Hades/a.png');
    final transport = _RecordingTransport();
    final controller = await controllerWith(
      publish: settingsWith(),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: transport,
      ),
    );

    final seen = <PublishActivity>[];
    controller.addListener(() {
      if (controller.isPublishing) {
        seen.add(controller.publishActivity);
      }
    });

    await controller.publish();

    expect(seen, isNotEmpty);
    final running = seen.last;
    expect(running.isRunning, isTrue);
    expect(running.title, 'Publishing · 50%');
    expect(running.detail, 'Uploading…');
    expect(running.progress, closeTo(0.5, 0.001));
  });

  test('stopping is only offered while a publish runs', () async {
    await capture('Steam/Hades/a.png');
    final transport = _CancellingTransport();
    final controller = await controllerWith(
      publish: settingsWith(),
      service: _StubbedPublishService(
        buildPath: build.path,
        transport: transport,
      ),
    );

    // Nothing running: asking to stop is harmless.
    controller.cancelPublish();
    expect(controller.publishActivity.isRunning, isFalse);

    transport.onUpload = controller.cancelPublish;
    await controller.publish();

    // The transport saw the stop the button asked for.
    expect(transport.wasCancelled, isTrue);
    expect(controller.message, contains('stopped'));
    expect(controller.publishActivity.isRunning, isFalse);
    expect(controller.publishActivity.isStopping, isFalse);
  });
}

/// Reports a run that was stopped partway.
class _StoppingTransport implements PublishTransport {
  @override
  String get name => 'stopping';

  @override
  Future<PublishOutcome> upload(
    PublishRequest request, {
    PublishProgressCallback? onProgress,
  }) async {
    return const PublishOutcome(
      uploaded: 2,
      skipped: 0,
      deleted: 0,
      bytes: 0,
      stopped: true,
    );
  }
}

/// Lets a test pull the stop while the upload is in flight, the way the
/// button does.
class _CancellingTransport implements PublishTransport {
  void Function()? onUpload;
  bool wasCancelled = false;

  @override
  String get name => 'cancelling';

  @override
  Future<PublishOutcome> upload(
    PublishRequest request, {
    PublishProgressCallback? onProgress,
  }) async {
    onUpload?.call();
    wasCancelled = request.cancellation.isCancelled;
    return PublishOutcome(
      uploaded: 1,
      skipped: 0,
      deleted: 0,
      bytes: 0,
      stopped: request.cancellation.isCancelled,
    );
  }
}

/// Keeps every line the controller writes, so a test can prove a secret was
/// replaced before it reached the file.
class _CapturingLog implements AppLog {
  final lines = <String>[];
  String Function(String value)? _redact;

  @override
  set redact(String Function(String value)? value) => _redact = value;

  void _record(String message) => lines.add(_redact?.call(message) ?? message);

  @override
  void debug(String message, {String? category}) => _record(message);

  @override
  void info(String message, {String? category}) => _record(message);

  @override
  void warning(
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  }) => _record(message);

  @override
  void error(
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  }) => _record(message);

  @override
  Future<String> read() async => lines.join('\n');

  @override
  Future<void> flush() async {}
}
