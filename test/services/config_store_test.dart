import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/config_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test('saves and loads application settings', () async {
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );
    const expected = AppSettings(
      outputPath: '/screenshots',
      diabloIV: ProviderSettings(enabled: true, sourcePath: '/diablo'),
    );

    await store.save(expected);
    final actual = await store.load();

    expect(actual.outputPath, expected.outputPath);
    expect(actual.diabloIV.enabled, isTrue);
    expect(actual.diabloIV.sourcePath, expected.diabloIV.sourcePath);
  });
}
