import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/providers/playstation_5_provider.dart';
import 'package:gaming_memories/services/video_metadata_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory source;
  late Directory output;
  late _FakeVideoDurationReader durationReader;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('gaming-memories-ps5-');
    output = await Directory.systemTemp.createTemp('gaming-memories-output-');
    durationReader = _FakeVideoDurationReader();
  });

  tearDown(() async {
    await source.delete(recursive: true);
    await output.delete(recursive: true);
  });

  AppSettings settings({bool enabled = true, String? sourcePath}) {
    return AppSettings(
      outputPath: output.path,
      diabloIV: const ProviderSettings.disabled(),
      playStation5: ProviderSettings(
        enabled: enabled,
        useCustomPath: true,
        sourcePath: sourcePath ?? source.path,
      ),
    );
  }

  test('imports screenshots and dates clips from their start time', () async {
    final game = Directory(p.join(source.path, 'Astro Bot'))..createSync();
    final screenshot = File(p.join(game.path, 'Astro Bot_20260920112233.jpg'));
    final clip = File(p.join(game.path, 'Astro Bot_20260920112303.webm'));
    final undated = File(p.join(game.path, 'Main Menu.jpg'));
    await screenshot.writeAsString('screenshot');
    await clip.writeAsString('clip');
    await undated.writeAsString('undated');
    await File(p.join(game.path, '.hidden_20260920112233.webm'))
        .writeAsString('ignored');
    await File(p.join(game.path, 'notes.mp4')).writeAsString('ignored');
    durationReader.durations[clip.path] = const Duration(seconds: 30);

    final result = await PlayStation5Provider(durationReader: durationReader)
        .collect(settings());

    final album = p.join(output.path, 'PlayStation 5', 'Astro Bot');
    expect(result.imported, 3);
    expect(result.skipped, 0);
    expect(File(p.join(album, '2026-09-20_11-22-33.jpg')).existsSync(), isTrue);
    expect(
      File(p.join(album, '2026-09-20_11-22-33.webm')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(album, 'Other', 'Undated_Main Menu.jpg')).existsSync(),
      isTrue,
    );
  });

  test('keeps both different duplicate captures using a hash suffix', () async {
    final game = Directory(p.join(source.path, 'Returnal'))..createSync();
    await File(p.join(game.path, 'Returnal_20260920112233.jpg'))
        .writeAsString('first screenshot');
    await File(p.join(game.path, 'Returnal_20260920112233_1.jpg'))
        .writeAsString('different screenshot');

    final result = await PlayStation5Provider(durationReader: durationReader)
        .collect(settings());

    final album = Directory(p.join(output.path, 'PlayStation 5', 'Returnal'));
    final captures = album
        .listSync()
        .whereType<File>()
        .where(
          (file) => p.basename(file.path).startsWith('2026-09-20_11-22-33'),
        )
        .toList();
    expect(result.imported, 2);
    expect(captures, hasLength(2));
    expect(
      captures.map((file) => p.basename(file.path)),
      contains('2026-09-20_11-22-33.jpg'),
    );
    expect(
      captures.any(
        (file) =>
            RegExp(r'^2026-09-20_11-22-33_[0-9a-f]{40}\.jpg$')
                .hasMatch(p.basename(file.path)),
      ),
      isTrue,
    );
  });

  test('keeps a clip end time when no duration is available', () async {
    final game = Directory(p.join(source.path, 'Ratchet'))..createSync();
    await File(p.join(game.path, 'Ratchet_20260920112233.webm'))
        .writeAsString('clip');

    final result = await PlayStation5Provider(durationReader: durationReader)
        .collect(settings());

    expect(result.imported, 1);
    expect(
      File(
        p.join(
          output.path,
          'PlayStation 5',
          'Ratchet',
          '2026-09-20_11-22-33.webm',
        ),
      ).existsSync(),
      isTrue,
    );
  });
}

class _FakeVideoDurationReader implements VideoDurationReader {
  final durations = <String, Duration>{};

  @override
  Future<Duration?> duration(File source) async => durations[source.path];
}
