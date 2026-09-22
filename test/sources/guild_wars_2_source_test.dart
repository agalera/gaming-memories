import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/sources/guild_wars_2_source.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory source;
  late Directory output;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('gaming-memories-source-');
    output = await Directory.systemTemp.createTemp('gaming-memories-output-');
  });

  tearDown(() async {
    await source.delete(recursive: true);
    await output.delete(recursive: true);
  });

  AppSettings settings({bool enabled = true}) => AppSettings(
    outputPath: output.path,
    guildWars2: SourceSettings(
      enabled: enabled,
      useCustomPath: true,
      sourcePath: source.path,
    ),
  );

  Future<File> writeScreenshot(
    String name,
    String content,
    DateTime modified,
  ) async {
    final file = File(p.join(source.path, name));
    await file.writeAsString(content);
    await file.setLastModified(modified);
    return file;
  }

  test('imports JPG files with the file modification date', () async {
    await writeScreenshot('gw001.JPG', 'first', DateTime(2026, 3, 14, 9, 5, 1));
    await writeScreenshot(
      'gw002.jpg',
      'second',
      DateTime(2026, 3, 15, 10, 6, 2),
    );
    await File(p.join(source.path, 'notes.png')).writeAsString('ignored');
    await Directory(p.join(source.path, 'nested')).create();

    final result = await const GuildWars2Source().collect(settings());

    expect(result.imported, 2);
    expect(result.skipped, 0);
    expect(
      File(p.join(output.path, 'PC', 'Guild Wars 2', '2026-03-14_09-05-01.jpg'))
          .existsSync(),
      isTrue,
    );
    expect(
      File(p.join(output.path, 'PC', 'Guild Wars 2', '2026-03-15_10-06-02.jpg'))
          .existsSync(),
      isTrue,
    );
  });

  test('skips a screenshot that is already in the library', () async {
    await writeScreenshot(
      'gw001.jpg',
      'same screenshot',
      DateTime(2026, 4, 2, 12, 30, 5),
    );
    const source = GuildWars2Source();

    await source.collect(settings());
    final result = await source.collect(settings());

    expect(result.imported, 0);
    expect(result.skipped, 1);
  });

  test('imports nothing while the source is disabled', () async {
    await writeScreenshot(
      'gw001.jpg',
      'screenshot',
      DateTime(2026, 4, 2, 12, 30, 5),
    );

    final result = await const GuildWars2Source().collect(
      settings(enabled: false),
    );

    expect(result.imported, 0);
    expect(result.skipped, 0);
    expect(Directory(p.join(output.path, 'PC')).existsSync(), isFalse);
  });
}
