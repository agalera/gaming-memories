import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/providers/playstation_4_provider.dart';
import 'package:gaming_memories/services/exiftool_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory source;
  late Directory output;
  late _FakeExifDateReader dateReader;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('gaming-memories-ps4-');
    output = await Directory.systemTemp.createTemp('gaming-memories-output-');
    dateReader = _FakeExifDateReader();
  });

  tearDown(() async {
    await source.delete(recursive: true);
    await output.delete(recursive: true);
  });

  AppSettings settings({bool enabled = true, String? sourcePath}) {
    return AppSettings(
      outputPath: output.path,
      diabloIV: const ProviderSettings.disabled(),
      playStation4: ProviderSettings(
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
    await datedClip.writeAsString('dated clip');
    await undatedClip.writeAsString('undated clip');
    await File(p.join(game.path, 'Thumbs.db')).writeAsString('ignored');
    await File(p.join(game.path, '._Bloodborne_20260920112233.mp4'))
        .writeAsString('ignored');
    dateReader.dates[screenshot.path] = DateTime(2026, 9, 19, 10, 20, 30);

    final result = await PlayStation4Provider(dateReader: dateReader)
        .collect(settings());

    final album = p.join(output.path, 'PlayStation 4', 'Bloodborne');
    expect(dateReader.availableChecked, isTrue);
    expect(result.imported, 3);
    expect(result.skipped, 0);
    expect(File(p.join(album, '2026-09-19_10-20-30.jpg')).existsSync(), isTrue);
    expect(File(p.join(album, '2026-09-20_11-22-33.mp4')).existsSync(), isTrue);
    expect(
      File(p.join(album, 'Other', 'Undated_Main Menu.mp4')).existsSync(),
      isTrue,
    );
  });

  test('skips a screenshot whose ExifTool date cannot be read', () async {
    final game = Directory(p.join(source.path, 'Journey'))..createSync();
    await File(p.join(game.path, 'Journey.jpg')).writeAsString('screenshot');

    final result = await PlayStation4Provider(dateReader: dateReader)
        .collect(settings());

    expect(result.imported, 0);
    expect(result.skipped, 1);
  });

  test('does not require ExifTool while disabled', () async {
    final result = await PlayStation4Provider(dateReader: dateReader)
        .collect(settings(enabled: false));

    expect(result.imported, 0);
    expect(dateReader.availableChecked, isFalse);
  });
}

class _FakeExifDateReader implements ExifDateReader {
  final dates = <String, DateTime>{};
  bool availableChecked = false;

  @override
  Future<void> ensureAvailable() async {
    availableChecked = true;
  }

  @override
  Future<DateTime> fileModifiedAt(File file) async => dates[file.path]!;
}
