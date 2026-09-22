import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/sources/playstation_4_source.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory source;
  late Directory output;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('gaming-memories-ps4-');
    output = await Directory.systemTemp.createTemp('gaming-memories-output-');
  });

  tearDown(() async {
    await source.delete(recursive: true);
    await output.delete(recursive: true);
  });

  AppSettings settings({bool enabled = true, String? sourcePath}) {
    return AppSettings(
      outputPath: output.path,
      playStation4: SourceSettings(
        enabled: enabled,
        useCustomPath: true,
        sourcePath: sourcePath ?? source.path,
      ),
    );
  }

  test('imports screenshots and clips into each game album', () async {
    final game = Directory(p.join(source.path, 'Bloodborne'))..createSync();
    final screenshot = File(p.join(game.path, 'Bloodborne.jpg'));
    final datedClip = File(p.join(game.path, 'Bloodborne_20260920112233.mp4'));
    final undatedClip = File(p.join(game.path, 'Main Menu.mp4'));
    await screenshot.writeAsString('screenshot');
    await screenshot.setLastModified(DateTime(2026, 9, 19, 10, 20, 30));
    await datedClip.writeAsString('dated clip');
    await undatedClip.writeAsString('undated clip');
    await File(p.join(game.path, 'Thumbs.db')).writeAsString('ignored');
    await File(p.join(game.path, '._Bloodborne_20260920112233.mp4'))
        .writeAsString('ignored');

    final result = await const PlayStation4Source().collect(settings());

    final album = p.join(output.path, 'PlayStation 4', 'Bloodborne');
    expect(result.imported, 3);
    expect(result.skipped, 0);
    expect(File(p.join(album, '2026-09-19_10-20-30.jpg')).existsSync(), isTrue);
    expect(File(p.join(album, '2026-09-20_11-22-33.mp4')).existsSync(), isTrue);
    expect(
      File(p.join(album, 'Other', 'Undated_Main Menu.mp4')).existsSync(),
      isTrue,
    );
  });

  test('skips a screenshot that is already in the library', () async {
    final game = Directory(p.join(source.path, 'Journey'))..createSync();
    final screenshot = File(p.join(game.path, 'Journey.jpg'));
    await screenshot.writeAsString('screenshot');
    await screenshot.setLastModified(DateTime(2026, 5, 6, 7, 8, 9));
    const playStation4 = PlayStation4Source();

    await playStation4.collect(settings());
    final result = await playStation4.collect(settings());

    expect(result.imported, 0);
    expect(result.skipped, 1);
    expect(
      File(
        p.join(
          output.path,
          'PlayStation 4',
          'Journey',
          '2026-05-06_07-08-09.jpg',
        ),
      ).existsSync(),
      isTrue,
    );
  });

  test('imports nothing while the source is disabled', () async {
    final game = Directory(p.join(source.path, 'Journey'))..createSync();
    await File(p.join(game.path, 'Journey.jpg')).writeAsString('screenshot');

    final result = await const PlayStation4Source().collect(
      settings(enabled: false),
    );

    expect(result.imported, 0);
    expect(result.skipped, 0);
    expect(
      Directory(p.join(output.path, 'PlayStation 4')).existsSync(),
      isFalse,
    );
  });
}
