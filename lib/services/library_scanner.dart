import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/library.dart';
import 'thumbnail_service.dart';

class LibraryScanner {
  const LibraryScanner({this.thumbnailService = const ThumbnailService()});

  final ThumbnailService thumbnailService;

  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
  static final _datePattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})',
  );

  Future<ScreenshotLibrary> scan(String outputPath) async {
    if (outputPath.trim().isEmpty) {
      return const ScreenshotLibrary.empty();
    }

    final root = Directory(expandUserPath(outputPath.trim()));
    if (!await root.exists()) {
      return const ScreenshotLibrary.empty();
    }

    final albums = <GameAlbum>[];
    final platformDirectories = await _directories(root);

    for (final platformDirectory in platformDirectories) {
      final gameDirectories = await _directories(platformDirectory);
      for (final gameDirectory in gameDirectories) {
        final screenshots = await _screenshots(
          gameDirectory,
          p.basename(platformDirectory.path),
          p.basename(gameDirectory.path),
        );

        if (screenshots.isNotEmpty) {
          albums.add(
            GameAlbum(
              platform: p.basename(platformDirectory.path),
              game: p.basename(gameDirectory.path),
              screenshots: screenshots,
            ),
          );
        }
      }
    }

    albums.sort((left, right) {
      final platformOrder = left.platform.compareTo(right.platform);
      return platformOrder == 0
          ? left.game.compareTo(right.game)
          : platformOrder;
    });

    return ScreenshotLibrary(albums: albums);
  }

  Future<List<Directory>> _directories(Directory parent) async {
    try {
      final directories = await parent
          .list(followLinks: false)
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();
      directories.sort((left, right) => left.path.compareTo(right.path));
      return directories;
    } on FileSystemException {
      return const [];
    }
  }

  Future<List<ScreenshotItem>> _screenshots(
    Directory directory,
    String platform,
    String game,
  ) async {
    final screenshots = <ScreenshotItem>[];

    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File ||
            !_isImage(entity.path) ||
            _isThumbnail(entity.path) ||
            p.basename(entity.path).toLowerCase() == 'cover.jpg') {
          continue;
        }

        final stat = await entity.stat();
        final thumbnailPath = await thumbnailService.ensureThumbnail(
          entity,
          stat,
        );
        screenshots.add(
          ScreenshotItem(
            path: entity.path,
            platform: platform,
            game: game,
            capturedAt: _dateFromName(entity.path) ?? stat.modified,
            thumbnailPath: thumbnailPath,
          ),
        );
      }
    } on FileSystemException {
      return screenshots;
    }

    screenshots.sort(
      (left, right) => right.capturedAt.compareTo(left.capturedAt),
    );
    return screenshots;
  }

  bool _isImage(String path) {
    return _imageExtensions.contains(p.extension(path).toLowerCase());
  }

  bool _isThumbnail(String path) {
    return p.basename(path).toLowerCase().endsWith('.thumb.jpg');
  }

  DateTime? _dateFromName(String path) {
    final match = _datePattern.firstMatch(p.basename(path));
    if (match == null) {
      return null;
    }

    try {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } on FormatException {
      return null;
    }
  }
}

String expandUserPath(String path) {
  if (path == '~') {
    return homeDirectory() ?? path;
  }

  if (path.startsWith('~/') || path.startsWith(r'~\')) {
    final home = homeDirectory();
    if (home != null) {
      return p.join(home, path.substring(2));
    }
  }

  return path;
}

String? homeDirectory() {
  return Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
}
