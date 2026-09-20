import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/library.dart';
import 'package:gaming_memories/services/library_scanner.dart';
import 'package:gaming_memories/services/thumbnail_service.dart';
import 'package:gaming_memories/services/video_metadata_service.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

void main() {
  test('builds albums and sorts the timeline by capture date', () async {
    final output = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => output.delete(recursive: true));
    final game = Directory(p.join(output.path, 'PC', 'Diablo IV'));
    await game.create(recursive: true);
    final older = File(p.join(game.path, '2026-01-02_03-04-05.jpg'));
    final newer = File(p.join(game.path, '2026-02-03_04-05-06.png'));
    await older.writeAsBytes(
      image.encodeJpg(image.Image(width: 800, height: 400)),
    );
    await newer.writeAsBytes(
      image.encodePng(image.Image(width: 400, height: 800)),
    );
    await File(p.join(game.path, 'notes.txt')).writeAsString('ignored');
    await File(p.join(game.path, 'cover.jpg')).writeAsString('cover');

    var library = await const LibraryScanner().scan(output.path);

    expect(library.albums, hasLength(1));
    expect(library.albums.single.platform, 'PC');
    expect(library.albums.single.game, 'Diablo IV');
    expect(library.timeline, hasLength(2));
    expect(library.timeline.first.capturedAt, DateTime(2026, 2, 3, 4, 5, 6));

    final thumbnail = File('${older.path}.thumb.jpg');
    expect(library.timeline.last.thumbnailPath, thumbnail.path);
    expect(await thumbnail.exists(), isTrue);
    var thumbnailImage = image.decodeJpg(await thumbnail.readAsBytes());
    expect(thumbnailImage, isNotNull);
    expect(thumbnailImage!.width, 360);
    expect(thumbnailImage.height, 180);

    await older.writeAsBytes(
      image.encodeJpg(image.Image(width: 400, height: 800)),
    );
    final changedAt = DateTime.now().add(const Duration(seconds: 2));
    await older.setLastModified(changedAt);

    library = await const LibraryScanner().scan(output.path);
    thumbnailImage = image.decodeJpg(await thumbnail.readAsBytes());

    expect(library.timeline, hasLength(2));
    expect(thumbnailImage, isNotNull);
    expect(thumbnailImage!.width, 180);
    expect(thumbnailImage.height, 360);
    expect((await thumbnail.stat()).modified, changedAt);
  });

  test('keeps sub-albums and scans video files', () async {
    final output = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => output.delete(recursive: true));
    final game = Directory(
      p.join(output.path, 'PlayStation 5', 'The Witcher 3'),
    );
    final other = Directory(p.join(game.path, 'Other'));
    final clips = Directory(p.join(other.path, 'Clips'));
    await clips.create(recursive: true);
    final first = File(p.join(other.path, '2026031822384700_s.mp4'));
    final second = File(p.join(clips.path, 'battle.mp4'));
    await first.writeAsBytes([1, 2, 3]);
    await second.writeAsBytes([4, 5, 6]);
    await File(p.join(other.path, 'cover.png')).writeAsBytes([7]);

    final library = await const LibraryScanner(
      thumbnailService: _FakeThumbnailService(),
      videoMetadataService: _FakeVideoMetadataService(),
    ).scan(output.path);

    final album = library.albums.single;
    expect(album.media, isEmpty);
    expect(album.allMedia, hasLength(2));
    expect(album.subAlbums.single.name, 'Other');
    expect(album.subAlbums.single.media.single.kind, MediaKind.video);
    expect(
      album.subAlbums.single.media.single.capturedAt,
      DateTime(2026, 3, 18, 22, 38, 47),
    );
    expect(
      album.subAlbums.single.media.single.duration,
      const Duration(seconds: 30),
    );
    expect(
      album.subAlbum(p.join('Other', 'Clips'))?.media.single.path,
      second.path,
    );
    expect(library.timeline, everyElement(isA<MediaItem>()));
  });

  test('reuses compatible video sidecars', () async {
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File(p.join(directory.path, 'clip.mp4'));
    final changedAt = DateTime(2026, 1, 1);
    await source.writeAsBytes([1, 2, 3]);
    await source.setLastModified(changedAt);
    final sourceStat = await source.stat();

    final thumbnail = File('${source.path}.thumb.jpg');
    await thumbnail.writeAsBytes(
      image.encodeJpg(image.Image(width: 320, height: 180)),
    );
    await thumbnail.setLastModified(changedAt.add(const Duration(seconds: 1)));

    final metadata = File('${source.path}.metadata.json');
    await metadata.writeAsString(
      jsonEncode({
        'ffmpeg_metadata': '29.933278',
        'duration': 29.933278,
        'timestamp': '2026-01-01T00:00:01Z',
      }),
    );
    await metadata.setLastModified(changedAt.add(const Duration(seconds: 1)));

    final thumbnailPath = await const ThumbnailService().ensureVideoThumbnail(
      source,
      sourceStat,
    );
    final duration = await const VideoMetadataService().ensureDuration(
      source,
      sourceStat,
    );

    expect(thumbnailPath, thumbnail.path);
    expect(duration, const Duration(milliseconds: 29933));
  });
}

class _FakeThumbnailService extends ThumbnailService {
  const _FakeThumbnailService();

  @override
  Future<String?> ensureVideoThumbnail(File source, FileStat sourceStat) async {
    return '${source.path}.thumb.jpg';
  }
}

class _FakeVideoMetadataService extends VideoMetadataService {
  const _FakeVideoMetadataService();

  @override
  Future<Duration?> ensureDuration(File source, FileStat sourceStat) async {
    return const Duration(seconds: 30);
  }
}
