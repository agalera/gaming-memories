import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/library.dart';
import 'library_scanner.dart';

class TimelineCache {
  const TimelineCache({this.filePath});

  const TimelineCache.disabled() : filePath = null;

  final String? filePath;

  Future<List<MediaItem>> load(String libraryPath) async {
    final path = filePath;
    if (path == null || libraryPath.trim().isEmpty) {
      return const [];
    }

    try {
      final source = await File(path).readAsString();
      final expectedLibraryPath = _normalizedPath(libraryPath);
      return await Isolate.run(
        () => _decodeTimeline(source, expectedLibraryPath),
      );
    } on Object {
      return const [];
    }
  }

  Future<void> save(String libraryPath, List<MediaItem> items) async {
    final path = filePath;
    if (path == null || libraryPath.trim().isEmpty) {
      return;
    }

    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File('$path.tmp');
    final payload = {
      'version': 1,
      'libraryPath': _normalizedPath(libraryPath),
      'items': items.map(_itemToJson).toList(growable: false),
    };
    final source = await Isolate.run(() => jsonEncode(payload));
    await temporary.writeAsString(source, flush: true);
    try {
      await temporary.rename(path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await temporary.rename(path);
    }
  }

  String _normalizedPath(String value) {
    final normalized = p.normalize(p.absolute(expandUserPath(value.trim())));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Map<String, Object?> _itemToJson(MediaItem item) {
    return {
      'path': item.path,
      'platform': item.platform,
      'game': item.game,
      'capturedAt': item.capturedAt.millisecondsSinceEpoch,
      'kind': item.kind.name,
      'subAlbumPath': item.subAlbumPath,
      'thumbnailPath': item.thumbnailPath,
      'durationMs': item.duration?.inMilliseconds,
      'sourceModifiedAtMs': item.sourceModifiedAt?.millisecondsSinceEpoch,
      'sourceSize': item.sourceSize,
    };
  }

  static List<MediaItem> _decodeTimeline(
    String source,
    String expectedLibraryPath,
  ) {
    final payload = jsonDecode(source);
    if (payload is! Map<String, dynamic> ||
        payload['version'] != 1 ||
        payload['libraryPath'] != expectedLibraryPath) {
      return const [];
    }

    final rawItems = payload['items'];
    if (rawItems is! List) {
      return const [];
    }

    final items = <MediaItem>[];
    for (final value in rawItems) {
      try {
        if (value is Map<String, dynamic>) {
          items.add(_itemFromJson(value));
        } else if (value is Map) {
          items.add(_itemFromJson(Map<String, dynamic>.from(value)));
        }
      } on Object {
        // Ignore one invalid entry and retain the rest of the cache.
      }
    }
    items.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return items;
  }

  static MediaItem _itemFromJson(Map<String, dynamic> value) {
    final kind = value['kind'] == MediaKind.video.name
        ? MediaKind.video
        : MediaKind.image;
    return MediaItem(
      path: value['path'] as String,
      platform: value['platform'] as String,
      game: value['game'] as String,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        value['capturedAt'] as int,
      ),
      kind: kind,
      subAlbumPath: value['subAlbumPath'] as String? ?? '',
      thumbnailPath: value['thumbnailPath'] as String?,
      duration: value['durationMs'] == null
          ? null
          : Duration(milliseconds: value['durationMs'] as int),
      sourceModifiedAt: value['sourceModifiedAtMs'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              value['sourceModifiedAtMs'] as int,
            ),
      sourceSize: value['sourceSize'] as int?,
    );
  }
}
