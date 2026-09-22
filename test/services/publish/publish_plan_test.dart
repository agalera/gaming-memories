import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/publish/gallery_builder.dart';
import 'package:gaming_memories/services/publish/gallery_renderer.dart';
import 'package:gaming_memories/services/publish/platform_covers.dart';
import 'package:gaming_memories/services/publish/publish_plan.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory library;
  late Directory build;

  setUp(() async {
    library = await Directory.systemTemp.createTemp('publish-plan-library');
    build = await Directory.systemTemp.createTemp('publish-plan-build');
  });

  tearDown(() async {
    for (final directory in [library, build]) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  Future<void> write(
    Directory root,
    String relativePath,
    String contents,
  ) async {
    final file = File(p.join(root.path, p.joinAll(relativePath.split('/'))));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<PublishPlan> buildPlan({
    List<String> excluded = const [],
    PlatformCoverSource covers = const NoPlatformCovers(),
  }) async {
    final root = await GalleryBuilder(platformCovers: covers).build(
      libraryPath: library.path,
      siteTitle: 'Memories',
      excluded: excluded,
    );
    final rendered = await GalleryRenderer(platformCovers: covers).render(
      root: root,
      buildPath: build.path,
      site: const PublishSiteSettings.defaults(),
    );
    return const PublishPlanner().plan(
      root: root,
      buildPath: build.path,
      renderedFiles: rendered.files,
      excludedAlbums: excluded,
    );
  }

  test(
    'merges the pages from the build tree with the library captures',
    () async {
      await write(library, 'Steam/Hades/a.png', 'image');
      await write(library, 'Steam/Hades/a.png.thumb.jpg', 'thumb');
      await write(library, 'Steam/Hades/cover.jpg', 'cover');

      final plan = await buildPlan();

      expect(plan.remotePaths, {
        'index.html',
        'Steam/index.html',
        'Steam/Hades/index.html',
        'Steam/Hades/a.png',
        'Steam/Hades/a.png.thumb.jpg',
        'Steam/Hades/cover.jpg',
      });

      final byPath = {for (final file in plan.files) file.remotePath: file};
      expect(byPath['Steam/Hades/index.html']!.root, PublishSourceRoot.build);
      expect(byPath['Steam/Hades/a.png']!.root, PublishSourceRoot.library);
      expect(
        byPath['Steam/Hades/a.png']!.localPath,
        p.join(library.path, 'Steam', 'Hades', 'a.png'),
      );
      expect(
        byPath['Steam/Hades/index.html']!.localPath,
        p.join(build.path, 'Steam', 'Hades', 'index.html'),
      );
    },
  );

  test('lists the remote folders parents first', () async {
    await write(library, 'Steam/Hades/Run 1/a.png', 'image');

    final plan = await buildPlan();

    expect(plan.directories, ['Steam', 'Steam/Hades', 'Steam/Hades/Run 1']);
  });

  test('an excluded album is neither planned nor forgotten', () async {
    await write(library, 'Steam/Hades/a.png', 'image');
    await write(library, 'Steam/Private/b.png', 'image');

    final plan = await buildPlan(excluded: ['Steam/Private']);

    expect(plan.remotePaths, isNot(contains('Steam/Private/b.png')));
    expect(plan.excludedAlbums, ['Steam/Private']);
  });

  test('carries the size and time of each local file', () async {
    await write(library, 'Steam/Hades/a.png', 'twelve chars');

    final plan = await buildPlan();
    final capture = plan.files.firstWhere(
      (file) => file.remotePath == 'Steam/Hades/a.png',
    );

    expect(capture.size, 12);
    expect(capture.modified.millisecondsSinceEpoch, greaterThan(0));
    expect(plan.totalBytes, greaterThan(12));
  });

  test('a bundled platform cover is published from the build tree', () async {
    await write(library, 'PC/Hades/a.png', 'image');

    final plan = await buildPlan(covers: const _PcCover());

    expect(plan.remotePaths, contains('PC/cover.png'));
    final cover = plan.files.firstWhere(
      (file) => file.remotePath == 'PC/cover.png',
    );
    expect(cover.root, PublishSourceRoot.build);
    expect(cover.localPath, p.join(build.path, 'PC', 'cover.png'));
    expect(cover.size, greaterThan(0));
  });

  test('an album cover still comes from the library', () async {
    await write(library, 'PC/Hades/cover.jpg', 'cover');
    await write(library, 'PC/Hades/a.png', 'image');

    final plan = await buildPlan(covers: const _PcCover());

    final album = plan.files.firstWhere(
      (file) => file.remotePath == 'PC/Hades/cover.jpg',
    );
    expect(album.root, PublishSourceRoot.library);
    expect(album.localPath, p.join(library.path, 'PC', 'Hades', 'cover.jpg'));
  });

  test('rsync protects a bundled cover the library cannot supply', () async {
    await write(library, 'PC/Hades/a.png', 'image');

    final plan = await buildPlan(covers: const _PcCover());
    final protected = plan.files
        .where((file) => file.root == PublishSourceRoot.build)
        .map((file) => file.remotePath)
        .toSet();

    // Without this the mirroring pass would delete it: the library has no
    // such file, so rsync sees it as extraneous on the remote.
    expect(protected, contains('PC/cover.png'));
  });

  test('captures are planned before the pages that link to them', () async {
    await write(library, 'Steam/Hades/a.png', 'image');
    await write(library, 'Steam/Hades/a.png.thumb.jpg', 'thumb');

    final plan = await buildPlan();
    final roots = plan.files.map((file) => file.root).toList();

    // A page arriving first would point at media still on its way.
    final lastCapture = roots.lastIndexOf(PublishSourceRoot.library);
    final firstPage = roots.indexOf(PublishSourceRoot.build);
    expect(firstPage, greaterThan(lastCapture));
  });

  test('within a root the order is still stable', () async {
    await write(library, 'Steam/Hades/b.png', 'image');
    await write(library, 'Steam/Hades/a.png', 'image');

    final plan = await buildPlan();
    final captures = plan.files
        .where((file) => file.root == PublishSourceRoot.library)
        .map((file) => file.remotePath)
        .toList();

    expect(captures, ['Steam/Hades/a.png', 'Steam/Hades/b.png']);
  });
}

class _PcCover implements PlatformCoverSource {
  const _PcCover();

  @override
  String? nameFor(String value) => value == 'PC' ? 'cover.png' : null;

  @override
  Future<List<int>?> bytesFor(String value) async =>
      value == 'PC' ? utf8.encode('the pc cover') : null;
}
