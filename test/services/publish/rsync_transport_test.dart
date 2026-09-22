import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/publish/publish_plan.dart';
import 'package:gaming_memories/services/publish/rsync_transport.dart';
import 'package:path/path.dart' as p;

const target = PublishTargetSettings(
  host: 'example.com',
  port: 2222,
  username: 'deploy',
  remotePath: '/srv/staticsites/screenshots.example.com/',
  credential: PublishCredentialKind.manualKey,
  keyPath: '/home/me/.ssh/id_ed25519',
  fileMode: '644',
  directoryMode: '755',
  deleteRemoved: true,
);

void main() {
  group('version', () {
    test('rejects the openrsync macOS ships', () {
      final version = RsyncVersion.parse(
        'openrsync: protocol version 29\nrsync version 2.6.9 compatible\n',
      );

      expect(version, isNotNull);
      expect(version!.isOpenRsync, isTrue);
      expect(version.isUsable, isFalse);
    });

    test('accepts rsync 3', () {
      final version = RsyncVersion.parse(
        'rsync  version 3.4.1  protocol version 32\n',
      );

      expect(version!.major, 3);
      expect(version.minor, 4);
      expect(version.isOpenRsync, isFalse);
      expect(version.isUsable, isTrue);
    });

    test('rejects an rsync older than 3', () {
      final version = RsyncVersion.parse(
        'rsync  version 2.6.9  protocol version 29\n',
      );

      expect(version!.isUsable, isFalse);
    });
  });

  group('protect rules', () {
    test('names each page it wrote, sorted', () {
      final rules = RsyncTransport.protectRules([
        'Steam/Hades/index.html',
        'index.html',
        'Steam/index.html',
      ]);

      expect(
        rules,
        'P /Steam/Hades/index.html\n'
        'P /Steam/index.html\n'
        'P /index.html\n',
      );
    });

    test('escapes the glob characters an album name can hold', () {
      final rules = RsyncTransport.protectRules([
        'PC/Hades [GOTY]/index.html',
        r'PC/What? *Really*/index.html',
      ]);

      // Only the opening bracket opens a character class, so it is the only
      // one that has to be escaped; the closing one is then ordinary.
      expect(rules, contains(r'P /PC/Hades \[GOTY]/index.html'));
      expect(rules, contains(r'P /PC/What\? \*Really\*/index.html'));
    });

    test('leaves the page of an album that is gone unprotected', () {
      final rules = RsyncTransport.protectRules(['Steam/Hades/index.html']);

      expect(rules, isNot(contains('Gone')));
    });
  });

  group('arguments', () {
    List<RsyncPass> passesFor({
      PublishTargetSettings? settings,
      List<String> excluded = const [],
    }) {
      return const RsyncTransport().buildArguments(
        target: settings ?? target,
        libraryPath: '/library/',
        buildPath: '/build',
        excluded: excluded,
        filterPath: '/build.rsync-filter',
      );
    }

    test('the captures go first, so a page never outruns its media', () {
      final passes = passesFor();

      expect(passes.map((pass) => pass.label), ['captures', 'pages']);
      expect(passes.map((pass) => pass.root), [
        PublishSourceRoot.library,
        PublishSourceRoot.build,
      ]);
    });

    test('the captures mirror and protect the pages about to be written', () {
      final captures = passesFor(excluded: ['Steam/Private', '/Secret/'])
          .first
          .arguments;

      expect(captures, contains('-rltz'));
      expect(captures, contains('--chmod=D755,F644'));
      expect(captures, contains('--delete-excluded'));
      expect(captures, contains('--filter=. /build.rsync-filter'));
      expect(captures, contains('--exclude=*.metadata.json'));
      // A library that used to be a gallery still holds that tool's pages,
      // and they must not land on top of the ones just rendered.
      expect(captures, contains('--exclude=index.html'));
      expect(captures, contains('--exclude=/Steam/Private/'));
      expect(captures, contains('--exclude=/Secret/'));
      expect(captures, contains('-e'));
      expect(
        captures,
        contains(
          'ssh -p 2222 -o BatchMode=yes '
          '-o StrictHostKeyChecking=accept-new '
          '-i /home/me/.ssh/id_ed25519',
        ),
      );
      expect(captures.sublist(captures.length - 2), [
        '/library/',
        'deploy@example.com:/srv/staticsites/screenshots.example.com/',
      ]);
    });

    test('the pages follow and delete nothing', () {
      final pages = passesFor().last.arguments;

      expect(pages, contains('-rltz'));
      expect(pages, contains('--chmod=D755,F644'));
      expect(pages, isNot(contains('--delete-excluded')));
      expect(pages, isNot(contains('--filter=. /build.rsync-filter')));
      expect(pages.sublist(pages.length - 2), [
        '/build/',
        'deploy@example.com:/srv/staticsites/screenshots.example.com/',
      ]);
    });

    test('mirroring off leaves the remote alone', () {
      final captures = passesFor(
        settings: target.copyWith(deleteRemoved: false),
      ).first.arguments;

      expect(captures, isNot(contains('--delete-excluded')));
      expect(captures, isNot(contains('--filter=. /build.rsync-filter')));
    });

    test('a host that is not known yet is accepted rather than refused', () {
      // BatchMode alone makes ssh refuse an unknown host, because it cannot
      // ask; accept-new takes the first key and still refuses a changed one.
      for (final pass in passesFor()) {
        expect(
          pass.arguments.any(
            (argument) => argument.contains('StrictHostKeyChecking=accept-new'),
          ),
          isTrue,
        );
      }
    });

    test('an automatic key leaves -i out, so ssh decides', () {
      final captures = passesFor(
        settings: target.copyWith(
          credential: PublishCredentialKind.automaticKey,
        ),
      ).first.arguments;

      // The key path is still stored, but a publish that did not choose it
      // must not force ssh onto it.
      expect(
        captures,
        contains(
          'ssh -p 2222 -o BatchMode=yes '
          '-o StrictHostKeyChecking=accept-new',
        ),
      );
      expect(captures.any((argument) => argument.contains('-i ')), isFalse);
    });

    test('a chosen key with no path leaves -i out too', () {
      final captures = passesFor(settings: target.copyWith(keyPath: ''))
          .first
          .arguments;

      expect(
        captures,
        contains(
          'ssh -p 2222 -o BatchMode=yes '
          '-o StrictHostKeyChecking=accept-new',
        ),
      );
    });
  });

  group('progress', () {
    PublishFile file(String path, PublishSourceRoot root, int size) {
      return PublishFile(
        remotePath: path,
        localPath: '/local/$path',
        root: root,
        size: size,
        modified: DateTime.utc(2026),
      );
    }

    test('each pass gets the share of the whole its bytes deserve', () {
      final shares = RsyncTransport.shares(
        PublishPlan(
          files: [
            file('a.png', PublishSourceRoot.library, 900),
            file('index.html', PublishSourceRoot.build, 100),
          ],
          directories: const [],
        ),
      );

      // Without this the second pass would restart the percentage at zero.
      expect(shares[PublishSourceRoot.library], closeTo(0.9, 0.001));
      expect(shares[PublishSourceRoot.build], closeTo(0.1, 0.001));
    });

    test('an empty plan splits the range rather than dividing by zero', () {
      final shares = RsyncTransport.shares(
        const PublishPlan(files: [], directories: []),
      );

      expect(shares[PublishSourceRoot.library], 0.5);
      expect(shares[PublishSourceRoot.build], 0.5);
    });

    test('the shares cover the whole publish exactly once', () {
      final shares = RsyncTransport.shares(
        PublishPlan(
          files: [
            file('a.png', PublishSourceRoot.library, 3),
            file('b.png', PublishSourceRoot.library, 4),
            file('index.html', PublishSourceRoot.build, 5),
          ],
          directories: const [],
        ),
      );

      expect(
        shares.values.reduce((sum, share) => sum + share),
        closeTo(1.0, 0.000001),
      );
    });
  });

  group('reading rsync progress', () {
    test('reads the percentage from a progress2 line', () {
      expect(
        RsyncTransport.progressOf('    1,234,567  45%    1.23MB/s    0:00:12'),
        closeTo(0.45, 0.001),
      );
      expect(
        RsyncTransport.progressOf(
          '  123,456  7%  1.00MB/s  0:00:05 (xfr#3, to-chk=10/14)',
        ),
        closeTo(0.07, 0.001),
      );
      expect(
        RsyncTransport.progressOf('32,768,000 100%  9.9MB/s  0:00:03'),
        1.0,
      );
    });

    test('a file name is not progress, even holding a percent sign', () {
      // rsync prints the names it sends on the same stream.
      expect(
        RsyncTransport.progressOf('Steam/100% Orange Juice/a.png'),
        isNull,
      );
      expect(RsyncTransport.progressOf('deleting Gone/old.png'), isNull);
      expect(RsyncTransport.progressOf(''), isNull);
      expect(
        RsyncTransport.progressOf('sending incremental file list'),
        isNull,
      );
    });
  });

  group('against a real rsync', () {
    final rsyncPath = Platform.environment['GAMING_MEMORIES_RSYNC'] ?? 'rsync';
    final runner = _PinnedRsyncRunner(rsyncPath);
    late Directory library;
    late Directory build;
    late Directory remote;

    Future<void> write(Directory root, String relativePath, String body) async {
      final file = File(p.join(root.path, p.joinAll(relativePath.split('/'))));
      await file.parent.create(recursive: true);
      await file.writeAsString(body);
    }

    setUp(() async {
      library = await Directory.systemTemp.createTemp('rsync-library');
      build = await Directory.systemTemp.createTemp('rsync-build');
      remote = await Directory.systemTemp.createTemp('rsync-remote');
    });

    tearDown(() async {
      for (final directory in [library, build, remote]) {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    });

    test('the two passes mirror the library while keeping the pages', () async {
      final rsync = RsyncTransport(runner: runner);
      final version = await rsync.probe();
      if (version == null || !version.isUsable) {
        markTestSkipped(
          'No rsync 3 on PATH; set GAMING_MEMORIES_RSYNC to one to prove '
          'the flag semantics.',
        );
        return;
      }

      await write(library, 'Steam/Hades/a.png', 'image');
      await write(library, 'Steam/Hades/a.png.thumb.jpg', 'thumb');
      await write(library, 'Steam/Hades/a.png.metadata.json', '{}');
      await write(library, 'PC/Hades [GOTY]/b.png', 'image');
      await write(library, 'Private/Secret/s.png', 'secret');

      // The library was a gallery built by another tool before this one,
      // so it still holds that tool's pages.
      await write(library, 'index.html', 'page from the old tool');
      await write(library, 'Steam/index.html', 'page from the old tool');
      await write(library, 'Steam/Hades/index.html', 'page from the old tool');

      await write(build, 'index.html', 'root page');
      await write(build, 'Steam/index.html', 'platform page');
      await write(build, 'Steam/Hades/index.html', 'album page');
      await write(build, 'PC/index.html', 'pc page');
      await write(build, 'PC/Hades [GOTY]/index.html', 'goty page');

      // What a previous publish left behind: an album that is gone, and an
      // album that has since been excluded.
      await write(remote, 'Gone/old.png', 'stale');
      await write(remote, 'Gone/index.html', 'stale page');
      await write(remote, 'Private/Secret/s.png', 'secret');
      await write(remote, 'Private/index.html', 'secret page');
      await write(remote, 'Steam/Hades/index.html', 'old album page');

      final filter = File('${build.path}.rsync-filter');
      await filter.writeAsString(
        RsyncTransport.protectRules([
          'index.html',
          'Steam/index.html',
          'Steam/Hades/index.html',
          'PC/index.html',
          'PC/Hades [GOTY]/index.html',
        ]),
      );
      addTearDown(() async {
        if (await filter.exists()) {
          await filter.delete();
        }
      });

      final passes = rsync.buildArguments(
        target: target,
        libraryPath: library.path,
        buildPath: build.path,
        excluded: ['Private'],
        filterPath: filter.path,
      );

      for (final pass in passes) {
        // Swap the ssh transport and the remote destination for local
        // paths: the flag semantics under test are the same either way.
        final local = pass.arguments
            .where((argument) => argument != '-e')
            .where((argument) => !argument.startsWith('ssh '))
            .toList();
        local[local.length - 1] = '${remote.path}/';
        final result = await Process.run(rsyncPath, local);
        expect(result.stderr, isEmpty, reason: '${result.stderr}');
        expect(result.exitCode, 0);
      }

      final left = remote
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => p.relative(file.path, from: remote.path))
          .map((path) => path.split(p.separator).join('/'))
          .toSet();

      expect(left, {
        'index.html',
        'Steam/index.html',
        'Steam/Hades/index.html',
        'Steam/Hades/a.png',
        'Steam/Hades/a.png.thumb.jpg',
        'PC/index.html',
        'PC/Hades [GOTY]/index.html',
        'PC/Hades [GOTY]/b.png',
      });
      // The rendered page won, rather than the one the library carries.
      expect(
        await File(p.join(remote.path, 'Steam', 'Hades', 'index.html'))
            .readAsString(),
        'album page',
      );
      expect(
        await File(p.join(remote.path, 'index.html')).readAsString(),
        'root page',
      );
      expect(
        await File(p.join(remote.path, 'Steam', 'index.html')).readAsString(),
        'platform page',
      );
      // The album that is gone took its page and its folder with it.
      expect(await Directory(p.join(remote.path, 'Gone')).exists(), isFalse);
      expect(await Directory(p.join(remote.path, 'Private')).exists(), isFalse);
    });
  });
}

/// Runs a named rsync rather than whatever is on PATH, so the flag semantics
/// can be proved against a real rsync 3 on a machine whose own rsync is
/// openrsync.
class _PinnedRsyncRunner implements ProcessRunner {
  const _PinnedRsyncRunner(this.executable);

  final String executable;

  @override
  Future<ProcessResult> run(String _, List<String> arguments) =>
      Process.run(executable, arguments);

  @override
  Future<Process> start(String _, List<String> arguments) =>
      Process.start(executable, arguments);
}
