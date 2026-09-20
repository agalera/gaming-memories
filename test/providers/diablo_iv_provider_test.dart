import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/providers/diablo_iv_provider.dart';
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

  AppSettings settings() => AppSettings(
    outputPath: output.path,
    diabloIV: ProviderSettings(
      enabled: true,
      useCustomPath: true,
      sourcePath: source.path,
    ),
  );

  test('copies images to the PC and Diablo IV album', () async {
    final screenshot = File(p.join(source.path, 'Screenshot001.JPG'));
    await screenshot.writeAsString('first screenshot');
    final capturedAt = DateTime(2026, 3, 14, 9, 5, 1);
    await screenshot.setLastModified(capturedAt);
    await File(p.join(source.path, 'notes.txt')).writeAsString('ignore me');

    final result = await const DiabloIVProvider().collect(settings());

    expect(result.imported, 1);
    expect(result.skipped, 0);
    expect(
      File(p.join(output.path, 'PC', 'Diablo IV', '2026-03-14_09-05-01.jpg'))
          .existsSync(),
      isTrue,
    );
  });

  test('adds the source hash when two images have one timestamp', () async {
    final capturedAt = DateTime(2026, 4, 2, 12, 30, 5);
    final first = File(p.join(source.path, 'Screenshot001.jpg'));
    final second = File(p.join(source.path, 'Screenshot002.jpg'));
    await first.writeAsString('first');
    await second.writeAsString('second');
    await first.setLastModified(capturedAt);
    await second.setLastModified(capturedAt);

    final result = await const DiabloIVProvider().collect(settings());
    final secondHash = sha1.convert(await second.readAsBytes()).toString();

    expect(result.imported, 2);
    expect(
      File(
        p.join(
          output.path,
          'PC',
          'Diablo IV',
          '2026-04-02_12-30-05_$secondHash.jpg',
        ),
      ).existsSync(),
      isTrue,
    );
  });

  test('skips screenshots already in the library', () async {
    final screenshot = File(p.join(source.path, 'Screenshot001.png'));
    await screenshot.writeAsString('same screenshot');
    await screenshot.setLastModified(DateTime(2026, 5, 1, 8));

    const provider = DiabloIVProvider();
    await provider.collect(settings());
    final result = await provider.collect(settings());

    expect(result.imported, 0);
    expect(result.skipped, 1);
  });
}
