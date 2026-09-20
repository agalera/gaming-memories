import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/providers/guild_wars_2_provider.dart';
import 'package:gaming_memories/services/exiftool_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory source;
  late Directory output;
  late _FakeExifDateReader dateReader;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('gaming-memories-source-');
    output = await Directory.systemTemp.createTemp('gaming-memories-output-');
    dateReader = _FakeExifDateReader();
  });

  tearDown(() async {
    await source.delete(recursive: true);
    await output.delete(recursive: true);
  });

  AppSettings settings({bool enabled = true}) => AppSettings(
    outputPath: output.path,
    guildWars2: ProviderSettings(
      enabled: enabled,
      useCustomPath: true,
      sourcePath: source.path,
    ),
  );

  test('imports JPG files with the ExifTool date', () async {
    final first = File(p.join(source.path, 'gw001.JPG'));
    final second = File(p.join(source.path, 'gw002.jpg'));
    await first.writeAsString('first');
    await second.writeAsString('second');
    await File(p.join(source.path, 'notes.png')).writeAsString('ignored');
    await Directory(p.join(source.path, 'nested')).create();
    dateReader.dates[first.path] = DateTime(2026, 3, 14, 9, 5, 1);
    dateReader.dates[second.path] = DateTime(2026, 3, 15, 10, 6, 2);

    final result = await GuildWars2Provider(dateReader: dateReader)
        .collect(settings());

    expect(dateReader.availableChecked, isTrue);
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
    final screenshot = File(p.join(source.path, 'gw001.jpg'));
    await screenshot.writeAsString('same screenshot');
    dateReader.dates[screenshot.path] = DateTime(2026, 4, 2, 12, 30, 5);
    final provider = GuildWars2Provider(dateReader: dateReader);

    await provider.collect(settings());
    final result = await provider.collect(settings());

    expect(result.imported, 0);
    expect(result.skipped, 1);
  });

  test('does not check ExifTool when the provider is disabled', () async {
    final result = await GuildWars2Provider(dateReader: dateReader)
        .collect(settings(enabled: false));

    expect(result.imported, 0);
    expect(result.skipped, 0);
    expect(dateReader.availableChecked, isFalse);
  });

  test('reports an unavailable ExifTool requirement', () async {
    dateReader.availableError = const FileSystemException(
      'ExifTool is required.',
    );

    expect(
      () => GuildWars2Provider(dateReader: dateReader).collect(settings()),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          contains('ExifTool is required'),
        ),
      ),
    );
  });

  test('parses the ExifTool date without a timezone shift', () {
    expect(
      parseExifToolDate('2026:03:14 09:05:01+02:00'),
      DateTime(2026, 3, 14, 9, 5, 1),
    );
    expect(parseExifToolDate('2026:02:31 09:05:01+02:00'), isNull);
    expect(parseExifToolDate('not a date'), isNull);
  });
}

class _FakeExifDateReader implements ExifDateReader {
  final dates = <String, DateTime>{};
  bool availableChecked = false;
  FileSystemException? availableError;

  @override
  Future<void> ensureAvailable() async {
    availableChecked = true;
    if (availableError case final error?) {
      throw error;
    }
  }

  @override
  Future<DateTime> fileModifiedAt(File file) async => dates[file.path]!;
}
