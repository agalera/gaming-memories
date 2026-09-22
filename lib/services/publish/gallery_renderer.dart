import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/app_settings.dart';
import 'gallery_assets.dart';
import 'gallery_node.dart';
import 'gallery_template.dart';
import 'platform_covers.dart';

class GalleryRenderResult {
  const GalleryRenderResult({
    required this.pages,
    required this.covers,
    required this.written,
    this.assets = const {},
  });

  /// Every page the build directory now holds, by its path below the site
  /// root.
  final Set<String> pages;

  /// The bundled platform covers it holds, the same way.
  final Set<String> covers;

  /// The files the pages link to that come from the app, such as the logo.
  final Set<String> assets;

  /// How many of those files this run actually rewrote.
  final int written;

  /// Everything the build directory contributes to the site.
  Set<String> get files => {...pages, ...covers, ...assets};
}

/// Writes the rendered pages into the app's build directory, one `index.html`
/// per album. The library folder itself is never written to.
class GalleryRenderer {
  const GalleryRenderer({
    this.platformCovers = const NoPlatformCovers(),
    this.assets = const NoGalleryAssets(),
  });

  /// Reads the bundled cover of a platform folder, which is written here
  /// rather than into the library.
  final PlatformCoverSource platformCovers;

  /// Files the pages link to that the library does not hold, such as the logo
  /// in the footer.
  final GalleryAssets assets;

  Future<GalleryRenderResult> render({
    required GalleryFolder root,
    required String buildPath,
    required PublishSiteSettings site,
  }) async {
    final directory = Directory(buildPath);
    await directory.create(recursive: true);

    final pages = <String>{};
    final covers = <String>{};
    final siteAssets = <String>{};
    var written = 0;

    // The logo goes down before the pages, so none of them links to a file
    // that is not there yet.
    final logo = await _writeLogo(buildPath);
    if (logo.present) {
      siteAssets.add(assets.logoFileName!);
    }
    if (logo.written) {
      written++;
    }

    final template = GalleryTemplate(
      site: site,
      logoPath: logo.present
          ? '/${Uri.encodeComponent(assets.logoFileName!)}'
          : null,
    );

    for (final page in root.pages()) {
      final target = File(p.join(buildPath, _toLocal(page.relativePath)));
      await target.parent.create(recursive: true);
      final bytes = utf8.encode(template.render(page));
      if (await _differs(target, bytes)) {
        await target.writeAsBytes(bytes, flush: true);
        written++;
      }
      pages.add(page.relativePath);

      final cover = await _writeCover(page.folder, buildPath);
      if (cover.written) {
        written++;
      }
      // Only a cover that is actually in the build directory is reported: a
      // bundled image that could not be read must not become a file the
      // upload then cannot find.
      if (cover.present) {
        covers.add(page.folder.coverRelativePath!);
      }
    }

    await _prune(directory, buildPath, {...pages, ...covers, ...siteAssets});

    return GalleryRenderResult(
      pages: pages,
      covers: covers,
      assets: siteAssets,
      written: written,
    );
  }

  /// Puts the logo in the build directory, so it is published beside the
  /// pages that link to it.
  Future<({bool present, bool written})> _writeLogo(String buildPath) async {
    const absent = (present: false, written: false);
    final name = assets.logoFileName;
    if (name == null) {
      return absent;
    }
    final bytes = await assets.logoBytes();
    if (bytes == null) {
      return absent;
    }

    final target = File(p.join(buildPath, name));
    await target.parent.create(recursive: true);
    if (!await _differs(target, bytes)) {
      return (present: true, written: false);
    }
    await target.writeAsBytes(bytes, flush: true);
    return (present: true, written: true);
  }

  /// Puts a folder's bundled cover in the build directory so the upload has a
  /// file to send. Says whether the cover is there afterwards, and whether
  /// this run is what put it there.
  Future<({bool present, bool written})> _writeCover(
    GalleryFolder folder,
    String buildPath,
  ) async {
    const absent = (present: false, written: false);
    final cover = folder.cover;
    final coverPath = folder.coverRelativePath;
    if (cover == null || coverPath == null || !cover.isBundled) {
      return absent;
    }

    final bytes = await platformCovers.bytesFor(cover.source);
    if (bytes == null) {
      return absent;
    }

    final target = File(p.join(buildPath, _toLocal(coverPath)));
    await target.parent.create(recursive: true);
    if (!await _differs(target, bytes)) {
      return (present: true, written: false);
    }
    await target.writeAsBytes(bytes, flush: true);
    return (present: true, written: true);
  }

  /// An unchanged page keeps its bytes and its modification time, so the
  /// transports skip it instead of uploading it again.
  Future<bool> _differs(File target, List<int> bytes) async {
    try {
      if (!await target.exists()) {
        return true;
      }
      final current = await target.readAsBytes();
      if (current.length != bytes.length) {
        return true;
      }
      for (var index = 0; index < bytes.length; index++) {
        if (current[index] != bytes[index]) {
          return true;
        }
      }
      return false;
    } on FileSystemException {
      return true;
    }
  }

  /// Drops pages for albums that are gone, so the build directory only ever
  /// describes the library as it is now.
  Future<void> _prune(
    Directory directory,
    String buildPath,
    Set<String> kept,
  ) async {
    final stale = <Directory>[];

    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is Directory) {
        stale.add(entry);
        continue;
      }
      if (entry is! File) {
        continue;
      }
      final relative = p
          .relative(entry.path, from: buildPath)
          .split(p.separator)
          .join('/');
      if (!kept.contains(relative)) {
        await entry.delete();
      }
    }

    // Deepest first, so a directory is only removed once its children are.
    stale.sort((left, right) => right.path.length.compareTo(left.path.length));
    for (final entry in stale) {
      if (await entry.list().isEmpty) {
        await entry.delete();
      }
    }
  }

  static String _toLocal(String relativePath) =>
      relativePath.split('/').join(p.separator);
}
