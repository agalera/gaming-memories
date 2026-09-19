import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/library_scanner.dart';
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
}
