import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as image;

class ThumbnailService {
  const ThumbnailService();

  static const maxSize = 360;
  static const quality = 85;

  String pathFor(String sourcePath) => '$sourcePath.thumb.jpg';

  Future<String?> ensureThumbnail(File source, FileStat sourceStat) async {
    final thumbnailPath = pathFor(source.path);
    final thumbnail = File(thumbnailPath);

    try {
      if (await _isCurrent(thumbnail, sourceStat)) {
        return thumbnailPath;
      }

      await Isolate.run(
        () =>
            _generateThumbnail(source.path, thumbnailPath, sourceStat.modified),
      );
      return thumbnailPath;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on image.ImageException {
      return null;
    } on StateError {
      return null;
    }
  }

  Future<bool> _isCurrent(File thumbnail, FileStat sourceStat) async {
    if (!await thumbnail.exists()) {
      return false;
    }

    final thumbnailStat = await thumbnail.stat();
    return thumbnailStat.size > 0 &&
        !thumbnailStat.modified.isBefore(sourceStat.modified);
  }
}

Future<void> _generateThumbnail(
  String sourcePath,
  String thumbnailPath,
  DateTime sourceModified,
) async {
  final sourceBytes = await File(sourcePath).readAsBytes();
  final decoded = image.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const FormatException('The screenshot format is not valid.');
  }

  final oriented = image.bakeOrientation(decoded);
  final longestSide = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final thumbnail = longestSide <= ThumbnailService.maxSize
      ? oriented
      : image.copyResize(
          oriented,
          width: oriented.width >= oriented.height
              ? ThumbnailService.maxSize
              : null,
          height: oriented.height > oriented.width
              ? ThumbnailService.maxSize
              : null,
          interpolation: image.Interpolation.cubic,
        );
  final bytes = image.encodeJpg(thumbnail, quality: ThumbnailService.quality);
  final temporary = File('$thumbnailPath.tmp');

  try {
    await temporary.writeAsBytes(bytes, flush: true);
    final destination = File(thumbnailPath);
    if (await destination.exists()) {
      await destination.delete();
    }
    await temporary.rename(thumbnailPath);
    await destination.setLastModified(sourceModified);
  } finally {
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
}
