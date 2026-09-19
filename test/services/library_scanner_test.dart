import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/library_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  test('builds albums and sorts the timeline by capture date', () async {
    final output = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => output.delete(recursive: true));
    final game = Directory(p.join(output.path, 'PC', 'Diablo IV'));
    await game.create(recursive: true);
    await File(p.join(game.path, '2026-01-02_03-04-05.jpg')).writeAsString('a');
    await File(p.join(game.path, '2026-02-03_04-05-06.png')).writeAsString('b');
    await File(p.join(game.path, 'notes.txt')).writeAsString('ignored');
    await File(p.join(game.path, 'cover.jpg')).writeAsString('cover');

    final library = await const LibraryScanner().scan(output.path);

    expect(library.albums, hasLength(1));
    expect(library.albums.single.platform, 'PC');
    expect(library.albums.single.game, 'Diablo IV');
    expect(library.timeline, hasLength(2));
    expect(library.timeline.first.capturedAt, DateTime(2026, 2, 3, 4, 5, 6));
  });
}
