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
      steam: SteamSettings(
        enabled: true,
        userdataPath: '/steam',
        onlineGallery: true,
        userId: '7656119',
        apiKey: 'secret',
        downloadCovers: false,
        ignoredGames: ['10'],
        customGames: {'20': 'Custom Game'},
      ),
    );

    await store.save(expected);
    final actual = await store.load();

    expect(actual.outputPath, expected.outputPath);
    expect(actual.diabloIV.enabled, isTrue);
    expect(actual.diabloIV.sourcePath, expected.diabloIV.sourcePath);
    expect(actual.steam.enabled, isTrue);
    expect(actual.steam.userdataPath, '/steam');
    expect(actual.steam.onlineGallery, isTrue);
    expect(actual.steam.userId, '7656119');
    expect(actual.steam.apiKey, 'secret');
    expect(actual.steam.downloadCovers, isFalse);
    expect(actual.steam.ignoredGames, ['10']);
    expect(actual.steam.customGames, {'20': 'Custom Game'});
  });
}
