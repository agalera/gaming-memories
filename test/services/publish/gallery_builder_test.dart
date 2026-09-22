import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/publish/gallery_builder.dart';
import 'package:gaming_memories/services/publish/gallery_node.dart';
import 'package:gaming_memories/services/publish/platform_covers.dart';
import 'package:path/path.dart' as p;

/// Bundles one cover, for the platform a test names.
class StubPlatformCovers implements PlatformCoverSource {
  const StubPlatformCovers(this.platform, {this.name = 'cover.png'});

  final String platform;
  final String name;

  @override
  String? nameFor(String value) => value == platform ? name : null;

  @override
  Future<List<int>?> bytesFor(String value) async =>
      value == platform ? utf8.encode('bundled $value') : null;
}

void main() {
  late Directory library;

  setUp(() async {
    library = await Directory.systemTemp.createTemp('gallery-builder');
  });

  tearDown(() async {
    if (await library.exists()) {
      await library.delete(recursive: true);
    }
  });

  Future<void> write(String relativePath, String contents) async {
    final file = File(p.join(library.path, p.joinAll(relativePath.split('/'))));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  GalleryFolder findFolder(GalleryFolder root, String relativePath) {
    return root
        .pages()
        .firstWhere((page) => page.folder.relativePath == relativePath)
        .folder;
  }

  test('collects captures and pairs them with their thumbnails', () async {
    await write('Steam/Hades/a.png', 'image');
    await write('Steam/Hades/a.png.thumb.jpg', 'thumb');
    await write('Steam/Hades/b.mp4', 'clip');

    final root = await const GalleryBuilder().build(
      libraryPath: library.path,
      siteTitle: 'Memories',
    );

    final album = findFolder(root, 'Steam/Hades');
    expect(album.files.map((file) => file.name), ['a.png', 'b.mp4']);
    expect(album.files.first.thumbnailPath, isNotNull);
    expect(album.files.last.thumbnailPath, isNull);
    expect(album.imageCount, 1);
    expect(album.videoCount, 1);
  });

  test('leaves the app caches and platform leftovers out', () async {
    await write('Steam/Hades/a.png', 'image');
    await write('Steam/Hades/a.png.metadata.json', '{"duration": 3}');
    await write('Steam/Hades/a.png.thumb.jpg.frame.jpg', 'frame');
    await write('Steam/Hades/.DS_Store', 'junk');
    await write('Steam/Hades/index.html', 'stale');
    await write('Steam/Hades/notes.txt', 'text');

    final root = await const GalleryBuilder().build(
      libraryPath: library.path,
      siteTitle: 'Memories',
    );

    expect(findFolder(root, 'Steam/Hades').files.map((file) => file.name), [
      'a.png',
    ]);
  });

  test('takes cover.* as the album cover rather than a capture', () async {
    await write('Steam/Hades/cover.jpg', 'cover');
    await write('Steam/Hades/a.png', 'image');

    final root = await const GalleryBuilder().build(
      libraryPath: library.path,
      siteTitle: 'Memories',
    );

    final album = findFolder(root, 'Steam/Hades');
    expect(album.cover?.name, 'cover.jpg');
    expect(album.cover?.isBundled, isFalse);
    expect(album.files.map((file) => file.name), ['a.png']);
    expect(album.coverWebPath, '/Steam/Hades/cover.jpg');
  });

  test('drops an excluded platform and an excluded album', () async {
    await write('Steam/Hades/a.png', 'image');
    await write('Steam/Private/b.png', 'image');
    await write('Secret/Game/c.png', 'image');

    final root = await const GalleryBuilder().build(
      libraryPath: library.path,
      siteTitle: 'Memories',
      excluded: ['Secret', 'Steam/Private'],
    );

    final paths = root.pages().map((page) => page.folder.relativePath).toSet();
    expect(paths, {'', 'Steam', 'Steam/Hades'});
  });

  test('leaves a folder with nothing in it out of the tree', () async {
    await write('Steam/Hades/a.png', 'image');
    await Directory(p.join(library.path, 'Steam', 'Empty')).create();

    final root = await const GalleryBuilder().build(
      libraryPath: library.path,
      siteTitle: 'Memories',
    );

    expect(findFolder(root, 'Steam').folders.map((f) => f.name), ['Hades']);
  });

  test('reads a clip duration from the cache beside it', () async {
    await write('Steam/Hades/b.mp4', 'clip');
    await write(
      'Steam/Hades/b.mp4.metadata.json',
      jsonEncode({'duration': 65.4}),
    );

    final root = await const GalleryBuilder().build(
      libraryPath: library.path,
      siteTitle: 'Memories',
    );

    final clip = findFolder(root, 'Steam/Hades').files.single;
    expect(clip.duration, const Duration(milliseconds: 65400));
    expect(clip.formattedDuration, '1:05');
  });

  test('a clip without a cached duration renders without one', () async {
    await write('Steam/Hades/b.mp4', 'clip');

    final root = await const GalleryBuilder().build(
      libraryPath: library.path,
      siteTitle: 'Memories',
    );

    expect(findFolder(root, 'Steam/Hades').files.single.formattedDuration, '');
  });

  test('nests sub-albums below their game', () async {
    await write('Steam/Hades/Run 1/a.png', 'image');
    await write('Steam/Hades/b.png', 'image');

    final root = await const GalleryBuilder().build(
      libraryPath: library.path,
      siteTitle: 'Memories',
    );

    final album = findFolder(root, 'Steam/Hades');
    expect(album.files.map((file) => file.name), ['b.png']);
    expect(album.folders.single.relativePath, 'Steam/Hades/Run 1');
    expect(album.folders.single.webPath, '/Steam/Hades/Run%201/');
  });

  test('a page carries the trail that leads to it', () async {
    await write('Steam/Hades/Run 1/a.png', 'image');

    final root = await const GalleryBuilder().build(
      libraryPath: library.path,
      siteTitle: 'Memories',
    );

    final page = root.pages().firstWhere(
      (page) => page.folder.relativePath == 'Steam/Hades/Run 1',
    );
    expect(page.trail.map((folder) => folder.relativePath), [
      '',
      'Steam',
      'Steam/Hades',
      'Steam/Hades/Run 1',
    ]);
    expect(page.relativePath, 'Steam/Hades/Run 1/index.html');
  });

  test('an album with no cover borrows the first thumbnail below it', () async {
    await write('Steam/Hades/a.png', 'image');
    await write('Steam/Hades/a.png.thumb.jpg', 'thumb');

    final root = await const GalleryBuilder().build(
      libraryPath: library.path,
      siteTitle: 'Memories',
    );

    expect(
      findFolder(root, 'Steam').coverWebPath,
      '/Steam/Hades/a.png.thumb.jpg',
    );
  });

  test('a platform folder takes the bundled cover', () async {
    await write('PlayStation 5/Astro/a.png', 'image');

    final root = await const GalleryBuilder(
      platformCovers: StubPlatformCovers('PlayStation 5', name: 'cover.jpg'),
    ).build(libraryPath: library.path, siteTitle: 'Memories');

    final platform = findFolder(root, 'PlayStation 5');
    expect(platform.cover?.name, 'cover.jpg');
    expect(platform.cover?.isBundled, isTrue);
    expect(platform.cover?.source, 'PlayStation 5');
    expect(platform.coverWebPath, '/PlayStation%205/cover.jpg');
    expect(platform.coverRelativePath, 'PlayStation 5/cover.jpg');
  });

  test('a cover in the library beats the bundled one', () async {
    await write('PC/cover.webp', 'mine');
    await write('PC/Hades/a.png', 'image');

    final root = await const GalleryBuilder(
      platformCovers: StubPlatformCovers('PC'),
    ).build(libraryPath: library.path, siteTitle: 'Memories');

    final platform = findFolder(root, 'PC');
    expect(platform.cover?.name, 'cover.webp');
    expect(platform.cover?.isBundled, isFalse);
  });

  test('a game album named after a platform gets no bundled cover', () async {
    await write('Steam/PC/a.png', 'image');

    final root = await const GalleryBuilder(
      platformCovers: StubPlatformCovers('PC'),
    ).build(libraryPath: library.path, siteTitle: 'Memories');

    expect(findFolder(root, 'Steam/PC').cover, isNull);
  });

  test('the site root takes no bundled cover', () async {
    await write('PC/Hades/a.png', 'image');

    final root = await const GalleryBuilder(
      platformCovers: StubPlatformCovers(''),
    ).build(libraryPath: library.path, siteTitle: 'Memories');

    expect(root.cover, isNull);
  });

  test('a platform with no bundled cover still borrows a thumbnail', () async {
    await write('Dreamcast/Game/a.png', 'image');
    await write('Dreamcast/Game/a.png.thumb.jpg', 'thumb');

    final root = await const GalleryBuilder(
      platformCovers: StubPlatformCovers('PC'),
    ).build(libraryPath: library.path, siteTitle: 'Memories');

    final platform = findFolder(root, 'Dreamcast');
    expect(platform.cover, isNull);
    expect(platform.coverWebPath, '/Dreamcast/Game/a.png.thumb.jpg');
  });
}
