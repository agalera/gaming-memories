import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'gallery_node.dart';
import 'platform_covers.dart';

/// Reads the library folder into the tree the gallery renders, leaving out the
/// excluded albums and the sidecars that belong to the app rather than to the
/// site.
class GalleryBuilder {
  const GalleryBuilder({this.platformCovers = const NoPlatformCovers()});

  /// Fills in the tile image for a platform folder, which no source writes a
  /// cover into.
  final PlatformCoverSource platformCovers;

  /// Names that are never published. The thumbnails are, because the pages
  /// link to them; the metadata caches are not, because only the app reads
  /// them.
  static const ignoredNames = {'.DS_Store', 'index.html', 'Thumbs.db'};

  static const _metadataSuffix = '.metadata.json';
  static const _thumbnailSuffix = '.thumb.jpg';

  /// Left behind by an interrupted video thumbnail.
  static const _frameSuffix = '.thumb.jpg.frame.jpg';

  Future<GalleryFolder> build({
    required String libraryPath,
    required String siteTitle,
    List<String> excluded = const [],
  }) async {
    final root = Directory(libraryPath);
    final normalizedExclusions = {
      for (final entry in excluded)
        if (_normalizeRelative(entry).isNotEmpty) _normalizeRelative(entry),
    };

    return _walk(
      directory: root,
      name: siteTitle,
      relativePath: '',
      excluded: normalizedExclusions,
    );
  }

  Future<GalleryFolder> _walk({
    required Directory directory,
    required String name,
    required String relativePath,
    required Set<String> excluded,
  }) async {
    final folders = <GalleryFolder>[];
    final files = <GalleryFile>[];
    GalleryCover? cover;
    var lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);

    final entries = await _entries(directory);

    // The sidecars are matched by name, so the whole folder has to be known
    // before any capture in it can be turned into a gallery file.
    final present = {for (final entry in entries) p.basename(entry.path)};

    for (final entry in entries) {
      final entryName = p.basename(entry.path);
      final childRelativePath = relativePath.isEmpty
          ? entryName
          : '$relativePath/$entryName';

      if (entry is Directory) {
        if (excluded.contains(childRelativePath)) {
          continue;
        }
        final child = await _walk(
          directory: entry,
          name: entryName,
          relativePath: childRelativePath,
          excluded: excluded,
        );
        if (child.isEmpty) {
          continue;
        }
        folders.add(child);
        if (child.lastUpdated.isAfter(lastUpdated)) {
          lastUpdated = child.lastUpdated;
        }
        continue;
      }

      if (entry is! File) {
        continue;
      }

      if (_isCover(entryName)) {
        cover = GalleryCover.fromLibrary(name: entryName, source: entry.path);
        continue;
      }

      if (_isIgnored(entryName)) {
        continue;
      }

      final kind = galleryFileKind(entryName);
      if (kind == null) {
        continue;
      }

      final stat = await entry.stat();
      final thumbnailName = '$entryName$_thumbnailSuffix';
      files.add(
        GalleryFile(
          name: entryName,
          sourcePath: entry.path,
          kind: kind,
          modified: stat.modified,
          capturedAt: capturedAtFromName(entryName) ?? stat.modified,
          size: stat.size,
          thumbnailPath: present.contains(thumbnailName)
              ? p.join(directory.path, thumbnailName)
              : null,
          duration: kind == GalleryFileKind.video
              ? await _cachedDuration(
                  p.join(directory.path, '$entryName$_metadataSuffix'),
                )
              : null,
        ),
      );
      if (stat.modified.isAfter(lastUpdated)) {
        lastUpdated = stat.modified;
      }
    }

    folders.sort((left, right) => left.name.compareTo(right.name));
    files.sort((left, right) => left.name.compareTo(right.name));

    return GalleryFolder(
      name: name,
      relativePath: relativePath,
      folders: folders,
      files: files,
      lastUpdated: lastUpdated.millisecondsSinceEpoch == 0
          ? DateTime.now()
          : lastUpdated,
      // A platform folder has no cover of its own, so the bundled one stands
      // in. A cover the user put there wins, which is why this runs last.
      cover: cover ?? _bundledCover(relativePath),
    );
  }

  Future<List<FileSystemEntity>> _entries(Directory directory) async {
    try {
      final entries = await directory.list(followLinks: false).toList();
      entries.sort((left, right) => left.path.compareTo(right.path));
      return entries;
    } on FileSystemException {
      return const [];
    }
  }

  /// Reads the duration the library already cached beside a clip. A clip the
  /// app has not probed yet simply renders without a length.
  Future<Duration?> _cachedDuration(String metadataPath) async {
    try {
      final file = File(metadataPath);
      if (!await file.exists()) {
        return null;
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, Object?>) {
        return null;
      }
      final seconds = switch (value['duration']) {
        num duration => duration.toDouble(),
        String duration => double.tryParse(duration),
        _ => null,
      };
      if (seconds == null || !seconds.isFinite || seconds <= 0) {
        return null;
      }
      return Duration(milliseconds: (seconds * 1000).round());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Only a top-level platform folder takes a bundled cover; a game album
  /// named after a platform is not one.
  GalleryCover? _bundledCover(String relativePath) {
    if (relativePath.isEmpty || relativePath.contains('/')) {
      return null;
    }
    final name = platformCovers.nameFor(relativePath);
    if (name == null) {
      return null;
    }
    return GalleryCover.bundled(name: name, source: relativePath);
  }

  static bool _isCover(String name) =>
      p.basenameWithoutExtension(name).toLowerCase() == 'cover';

  static bool _isIgnored(String name) =>
      ignoredNames.contains(name) ||
      name.endsWith(_metadataSuffix) ||
      name.endsWith(_thumbnailSuffix) ||
      name.endsWith(_frameSuffix);

  static String _normalizeRelative(String value) {
    final trimmed = value.trim().replaceAll(r'\', '/');
    return trimmed
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .join('/');
  }
}
