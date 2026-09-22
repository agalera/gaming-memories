import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/publish/gallery_builder.dart';
import 'package:gaming_memories/services/publish/gallery_assets.dart';
import 'package:gaming_memories/services/publish/gallery_renderer.dart';
import 'package:gaming_memories/services/publish/platform_covers.dart';
import 'package:path/path.dart' as p;

/// Bundles a cover for one platform, so the renderer can be exercised without
/// the real asset bundle.
class StubPlatformCovers implements PlatformCoverSource {
  const StubPlatformCovers(this.platform, this.body);

  final String platform;
  final String body;

  @override
  String? nameFor(String value) => value == platform ? 'cover.png' : null;

  @override
  Future<List<int>?> bytesFor(String value) async =>
      value == platform ? utf8.encode(body) : null;
}

void main() {
  late Directory library;
  late Directory build;

  setUp(() async {
    library = await Directory.systemTemp.createTemp('renderer-library');
    build = await Directory.systemTemp.createTemp('renderer-build');
  });

  tearDown(() async {
    for (final directory in [library, build]) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  Future<void> write(String relativePath, String contents) async {
    final file = File(p.join(library.path, p.joinAll(relativePath.split('/'))));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<GalleryRenderResult> render({
    PlatformCoverSource? covers,
    GalleryAssets assets = const NoGalleryAssets(),
  }) async {
    final source = covers ?? const NoPlatformCovers();
    final root = await GalleryBuilder(platformCovers: source)
        .build(libraryPath: library.path, siteTitle: 'Memories');
    return GalleryRenderer(platformCovers: source, assets: assets).render(
      root: root,
      buildPath: build.path,
      site: const PublishSiteSettings.defaults(),
    );
  }

  test('writes one page per album and never into the library', () async {
    await write('Steam/Hades/a.png', 'image');

    final result = await render();

    expect(result.pages, {
      'index.html',
      'Steam/index.html',
      'Steam/Hades/index.html',
    });
    expect(
      await File(p.join(build.path, 'Steam', 'Hades', 'index.html')).exists(),
      isTrue,
    );
    expect(
      await File(p.join(library.path, 'Steam', 'Hades', 'index.html')).exists(),
      isFalse,
    );
  });

  test('leaves an unchanged page alone so the upload skips it', () async {
    await write('Steam/Hades/a.png', 'image');

    final first = await render();
    final page = File(p.join(build.path, 'Steam', 'Hades', 'index.html'));
    final before = await page.lastModified();

    final second = await render();

    expect(first.written, 3);
    expect(second.written, 0);
    expect(await page.lastModified(), before);
  });

  test('drops the pages of an album that is gone', () async {
    await write('Steam/Hades/a.png', 'image');
    await write('Steam/Gone/b.png', 'image');
    await render();
    expect(
      await Directory(p.join(build.path, 'Steam', 'Gone')).exists(),
      isTrue,
    );

    await Directory(p.join(library.path, 'Steam', 'Gone'))
        .delete(recursive: true);
    final result = await render();

    expect(result.pages, isNot(contains('Steam/Gone/index.html')));
    expect(
      await Directory(p.join(build.path, 'Steam', 'Gone')).exists(),
      isFalse,
    );
  });

  test('writes a bundled platform cover beside its page', () async {
    await write('PC/Hades/a.png', 'image');

    final result = await render(
      covers: const StubPlatformCovers('PC', 'the pc cover'),
    );

    expect(result.covers, {'PC/cover.png'});
    expect(result.files, contains('PC/index.html'));
    final cover = File(p.join(build.path, 'PC', 'cover.png'));
    expect(await cover.readAsString(), 'the pc cover');

    // The library keeps holding captures only.
    expect(
      await File(p.join(library.path, 'PC', 'cover.png')).exists(),
      isFalse,
    );
  });

  test('an unchanged cover is left alone on the next run', () async {
    await write('PC/Hades/a.png', 'image');
    const covers = StubPlatformCovers('PC', 'the pc cover');

    final first = await render(covers: covers);
    final cover = File(p.join(build.path, 'PC', 'cover.png'));
    final before = await cover.lastModified();

    final second = await render(covers: covers);

    expect(first.written, 4);
    expect(second.written, 0);
    expect(await cover.lastModified(), before);
  });

  test('pruning keeps the covers and drops the ones no longer used', () async {
    await write('PC/Hades/a.png', 'image');
    await write('Pico-8/Game/b.png', 'image');
    const covers = _TwoPlatformCovers();

    await render(covers: covers);
    expect(
      await File(p.join(build.path, 'Pico-8', 'cover.png')).exists(),
      isTrue,
    );

    await Directory(p.join(library.path, 'Pico-8')).delete(recursive: true);
    final result = await render(covers: covers);

    expect(result.covers, {'PC/cover.png'});
    expect(await File(p.join(build.path, 'PC', 'cover.png')).exists(), isTrue);
    expect(await Directory(p.join(build.path, 'Pico-8')).exists(), isFalse);
  });

  test('a cover that cannot be read is not published at all', () async {
    await write('PC/Hades/a.png', 'image');

    final result = await render(covers: const _UnreadableCovers());

    // Reporting it would hand the upload a file that is not there.
    expect(result.covers, isEmpty);
    expect(result.pages, contains('PC/index.html'));
    expect(await File(p.join(build.path, 'PC', 'cover.png')).exists(), isFalse);
  });
  test('the logo is published beside the pages that link to it', () async {
    await write('PC/Hades/a.png', 'image');

    final result = await render(assets: const _StubAssets('the logo'));

    expect(result.assets, {'gaming-memories.webp'});
    expect(result.files, contains('gaming-memories.webp'));
    final logo = File(p.join(build.path, 'gaming-memories.webp'));
    expect(await logo.readAsString(), 'the logo');

    final page = await File(p.join(build.path, 'PC', 'index.html'))
        .readAsString();
    expect(page, contains('src="/gaming-memories.webp"'));
  });

  test('an unchanged logo is left alone on the next run', () async {
    await write('PC/Hades/a.png', 'image');
    const assets = _StubAssets('the logo');

    final first = await render(assets: assets);
    final logo = File(p.join(build.path, 'gaming-memories.webp'));
    final before = await logo.lastModified();

    final second = await render(assets: assets);

    expect(first.written, greaterThan(second.written));
    expect(second.written, 0);
    expect(await logo.lastModified(), before);
  });

  test('a build with no logo links to none', () async {
    await write('PC/Hades/a.png', 'image');

    final result = await render();

    expect(result.assets, isEmpty);
    final page = await File(p.join(build.path, 'PC', 'index.html'))
        .readAsString();
    expect(page, isNot(contains('class="footer-logo"')));
  });

  test('a logo that cannot be read is not linked either', () async {
    await write('PC/Hades/a.png', 'image');

    final result = await render(assets: const _StubAssets(null));

    // Linking it would point every page at a file that is not there.
    expect(result.assets, isEmpty);
    expect(
      await File(p.join(build.path, 'gaming-memories.webp')).exists(),
      isFalse,
    );
  });
}

/// Ships whatever a test says, or nothing when the body is null.
class _StubAssets implements GalleryAssets {
  const _StubAssets(this.body);

  final String? body;

  @override
  String? get logoFileName => 'gaming-memories.webp';

  @override
  Future<List<int>?> logoBytes() async =>
      body == null ? null : utf8.encode(body!);
}

/// Bundles a cover for both platforms the pruning test uses.
class _TwoPlatformCovers implements PlatformCoverSource {
  const _TwoPlatformCovers();

  static const _known = {'PC', 'Pico-8'};

  @override
  String? nameFor(String value) => _known.contains(value) ? 'cover.png' : null;

  @override
  Future<List<int>?> bytesFor(String value) async =>
      _known.contains(value) ? utf8.encode('cover for $value') : null;
}

/// Names a cover it then cannot produce, the way a missing asset behaves.
class _UnreadableCovers implements PlatformCoverSource {
  const _UnreadableCovers();

  @override
  String? nameFor(String value) => value == 'PC' ? 'cover.png' : null;

  @override
  Future<List<int>?> bytesFor(String value) async => null;
}
