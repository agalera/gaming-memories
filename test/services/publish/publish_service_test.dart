import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/publish/publish_credentials.dart';
import 'package:gaming_memories/services/publish/publish_service.dart';
import 'package:gaming_memories/services/publish/ssh_agent_client.dart';
import 'package:gaming_memories/services/publish/rsync_transport.dart';
import 'package:path/path.dart' as p;

/// Answers `rsync --version` with whatever a test needs, without running one.
class _FakeRunner implements ProcessRunner {
  _FakeRunner(this.version);

  final String? version;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    if (version == null) {
      throw const ProcessException('rsync', ['--version'], 'not found');
    }
    return ProcessResult(0, 0, version, '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments) {
    throw UnimplementedError();
  }
}

/// Holds nothing, so a test never reaches the machine's own SSH agent.
class _EmptyAgent implements SshAgentFactory {
  const _EmptyAgent();

  @override
  SshAgentClient create({String? socketPath}) => SshAgentClient(socketPath: '');
}

PublishService serviceWith(
  String? rsyncVersion, {
  String buildPath = '/build',
  String? homeDirectory,
}) {
  return PublishService(
    buildPath: buildPath,
    rsync: RsyncTransport(runner: _FakeRunner(rsyncVersion)),
    credentials: PublishCredentialResolver(
      agent: const _EmptyAgent(),
      homeDirectory: homeDirectory ?? '/definitely/not/a/home',
    ),
  );
}

const enabledTarget = PublishTargetSettings(
  host: 'example.com',
  port: 22,
  username: 'deploy',
  remotePath: '/srv/site',
  keyPath: '',
  fileMode: '644',
  directoryMode: '755',
  deleteRemoved: true,
);

const enabled = PublishSettings(enabled: true, target: enabledTarget);

PublishSettings withKey(String path) => enabled.copyWith(
  target: enabledTarget.copyWith(
    credential: PublishCredentialKind.manualKey,
    keyPath: path,
  ),
);

const rsync3 = 'rsync  version 3.4.1  protocol version 32\n';
const openRsync =
    'openrsync: protocol version 29\nrsync version 2.6.9 compatible\n';

void main() {
  group('validate', () {
    test('refuses while publishing is off', () {
      expect(
        PublishService.validate(
          libraryPath: '/library',
          settings: const PublishSettings.disabled(),
        ),
        contains('turned off'),
      );
    });

    test('names the first missing field', () {
      expect(
        PublishService.validate(libraryPath: '', settings: enabled),
        contains('library folder'),
      );
      expect(
        PublishService.validate(
          libraryPath: '/library',
          settings: const PublishSettings(enabled: true),
        ),
        contains('host'),
      );
      expect(
        PublishService.validate(
          libraryPath: '/library',
          settings: PublishSettings(
            enabled: true,
            target: enabledTarget.copyWith(username: ''),
          ),
        ),
        contains('user name'),
      );
      expect(
        PublishService.validate(
          libraryPath: '/library',
          settings: PublishSettings(
            enabled: true,
            target: enabledTarget.copyWith(remotePath: ''),
          ),
        ),
        contains('remote folder'),
      );
    });

    test('a complete target passes', () {
      expect(
        PublishService.validate(
          libraryPath: '/library',
          settings: withKey('/home/me/.ssh/id_ed25519'),
        ),
        isNull,
      );
    });

    test('does not force a key: automatic needs nothing', () {
      expect(
        PublishService.validate(libraryPath: '/library', settings: enabled),
        isNull,
      );
    });

    test('a chosen key kind does need a path', () {
      expect(
        PublishService.validate(
          libraryPath: '/library',
          settings: enabled.copyWith(
            target: enabledTarget.copyWith(
              credential: PublishCredentialKind.manualKey,
            ),
          ),
        ),
        contains('SSH key'),
      );
    });
  });

  group('transport selection', () {
    late Directory keys;

    setUp(() async {
      keys = await Directory.systemTemp.createTemp('publish-keys');
    });

    tearDown(() async {
      if (await keys.exists()) {
        await keys.delete(recursive: true);
      }
    });

    Future<String> plainKey(String name) async {
      final file = File(p.join(keys.path, name));
      await file.writeAsString('not really a key');
      return file.path;
    }

    test('a forced choice is honoured whatever is on PATH', () async {
      final service = serviceWith(null);

      expect(
        (await service.selectTransport(
          enabled.copyWith(transport: PublishTransportKind.rsync),
        )).transport.name,
        'rsync',
      );
      expect(
        (await service.selectTransport(
          enabled.copyWith(transport: PublishTransportKind.sftp),
        )).transport.name,
        'SFTP',
      );
    });

    test('automatic prefers a usable rsync', () async {
      final choice = await serviceWith(rsync3)
          .selectTransport(withKey(await plainKey('id')));

      expect(choice.transport.name, 'rsync');
      expect(choice.reason, contains('on PATH'));
    });

    test('an automatic key lets ssh decide, so rsync can run', () async {
      final choice = await serviceWith(rsync3).selectTransport(enabled);

      expect(choice.transport.name, 'rsync');
    });

    test('a password cannot go through rsync', () async {
      final choice = await serviceWith(rsync3).selectTransport(
        enabled.copyWith(
          target: enabledTarget.copyWith(
            credential: PublishCredentialKind.password,
          ),
        ),
      );

      expect(choice.transport.name, 'SFTP');
      expect(choice.reason, contains('password'));
    });

    test('automatic falls back when rsync is missing', () async {
      final choice = await serviceWith(null).selectTransport(enabled);

      expect(choice.transport.name, 'SFTP');
      expect(choice.reason, contains('not on PATH'));
    });

    test('automatic refuses openrsync', () async {
      final choice = await serviceWith(openRsync).selectTransport(enabled);

      expect(choice.transport.name, 'SFTP');
      expect(choice.reason, contains('openrsync'));
    });

    test('automatic refuses an rsync older than 3', () async {
      final choice = await serviceWith(
        'rsync  version 2.6.9  protocol version 29\n',
      ).selectTransport(enabled);

      expect(choice.transport.name, 'SFTP');
      expect(choice.reason, contains('older than 3.0'));
    });

    test('a key path with a space cannot go through rsync', () async {
      final choice = await serviceWith(rsync3)
          .selectTransport(withKey(await plainKey('my key')));

      expect(choice.transport.name, 'SFTP');
      expect(choice.reason, contains('space'));
    });
  });
}
