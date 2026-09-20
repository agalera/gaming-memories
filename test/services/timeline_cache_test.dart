import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/library.dart';
import 'package:gaming_memories/services/timeline_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  test('stores and restores timeline media for one library', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gaming-memories-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final cache = TimelineCache(
      filePath: p.join(directory.path, 'timeline-cache.json'),
    );
    final newer = MediaItem(
      path: p.join(directory.path, 'PC', 'Game', 'new.jpg'),
      platform: 'PC',
      game: 'Game',
      capturedAt: DateTime(2026, 2, 1),
      kind: MediaKind.image,
      thumbnailPath: '/cache/new.thumb.jpg',
      sourceModifiedAt: DateTime(2026, 2, 1, 12),
      sourceSize: 2048,
    );
    final older = MediaItem(
      path: p.join(directory.path, 'PC', 'Game', 'old.mp4'),
      platform: 'PC',
      game: 'Game',
      capturedAt: DateTime(2026, 1, 1),
      kind: MediaKind.video,
      subAlbumPath: 'Clips',
      thumbnailPath: '/cache/old.thumb.jpg',
      duration: const Duration(seconds: 42),
    );

    await cache.save(directory.path, [older, newer]);
    final restored = await cache.load(directory.path);

    expect(restored.map((item) => item.path), [newer.path, older.path]);
    expect(restored.last.kind, MediaKind.video);
    expect(restored.last.subAlbumPath, 'Clips');
    expect(restored.last.duration, const Duration(seconds: 42));
    expect(restored.first.sourceModifiedAt, DateTime(2026, 2, 1, 12));
    expect(restored.first.sourceSize, 2048);
    expect(await cache.load(p.join(directory.path, 'another')), isEmpty);
  });

  test('ignores an invalid cache file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gaming-memories-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'timeline-cache.json');
    await File(path).writeAsString('{invalid');

    final restored = await TimelineCache(filePath: path).load(directory.path);

    expect(restored, isEmpty);
  });
}
