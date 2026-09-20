import 'dart:convert';
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
      themeMode: AppThemeMode.dark,
      battleNet: ProviderSettings(
        enabled: true,
        useCustomPath: true,
        sourcePath: '/diablo',
      ),
      guildWars2: ProviderSettings(
        enabled: true,
        useCustomPath: true,
        sourcePath: '/guild-wars-2',
      ),
      hytale: ProviderSettings(
        enabled: true,
        useCustomPath: false,
        sourcePath: '/Users/alice/Pictures/Hytale Screenshots',
        downloadCovers: true,
      ),
      minecraft: ProviderSettings(
        enabled: true,
        useCustomPath: true,
        sourcePath: '/minecraft/screenshots',
      ),
      playStation4: ProviderSettings(
        enabled: true,
        useCustomPath: true,
        sourcePath: '/playstation-4',
      ),
      playStation5: ProviderSettings(
        enabled: true,
        useCustomPath: true,
        sourcePath: '/playstation-5',
      ),
      steam: SteamSettings(
        enabled: true,
        useCustomPath: true,
        userdataPath: '/steam',
        onlineGallery: true,
        userId: '7656119',
        apiKey: 'secret',
        downloadCovers: false,
        ignoredGames: ['10'],
        customGames: {'20': 'Custom Game'},
      ),
      folderGrants: {
        'library': FolderGrant(
          platform: 'macos',
          path: '/screenshots',
          access: FolderGrantAccess.readWrite,
          bookmark: 'Ym9va21hcms=',
        ),
      },
    );

    await store.save(expected);
    final actual = await store.load();

    expect(actual.outputPath, expected.outputPath);
    expect(actual.themeMode, AppThemeMode.dark);
    expect(actual.battleNet.enabled, isTrue);
    expect(actual.battleNet.useCustomPath, isTrue);
    expect(actual.battleNet.sourcePath, expected.battleNet.sourcePath);
    expect(actual.guildWars2.enabled, isTrue);
    expect(actual.guildWars2.useCustomPath, isTrue);
    expect(actual.guildWars2.sourcePath, '/guild-wars-2');
    expect(actual.hytale.enabled, isTrue);
    expect(actual.hytale.useCustomPath, isFalse);
    expect(
      actual.hytale.sourcePath,
      '/Users/alice/Pictures/Hytale Screenshots',
    );
    expect(actual.hytale.downloadCovers, isTrue);
    expect(actual.minecraft.enabled, isTrue);
    expect(actual.minecraft.useCustomPath, isTrue);
    expect(actual.minecraft.sourcePath, '/minecraft/screenshots');
    expect(actual.playStation4.enabled, isTrue);
    expect(actual.playStation4.useCustomPath, isTrue);
    expect(actual.playStation4.sourcePath, '/playstation-4');
    expect(actual.playStation5.enabled, isTrue);
    expect(actual.playStation5.useCustomPath, isTrue);
    expect(actual.playStation5.sourcePath, '/playstation-5');
    expect(actual.steam.enabled, isTrue);
    expect(actual.steam.useCustomPath, isTrue);
    expect(actual.steam.userdataPath, '/steam');
    expect(actual.steam.onlineGallery, isTrue);
    expect(actual.steam.userId, '7656119');
    expect(actual.steam.apiKey, 'secret');
    expect(actual.steam.downloadCovers, isFalse);
    expect(actual.steam.ignoredGames, ['10']);
    expect(actual.steam.customGames, {'20': 'Custom Game'});
    expect(actual.folderGrants['library']?.path, '/screenshots');
    expect(actual.folderGrants['library']?.access, FolderGrantAccess.readWrite);
    final json = jsonDecode(await File(store.filePath).readAsString()) as Map;
    expect(json['version'], 10);
    expect(json['diabloIV'], isNull);
    expect(json['battleNet'], isA<Map>());
    expect(File('${store.filePath}.tmp').existsSync(), isFalse);
  });

  test('migrates legacy automatic and custom path values', () async {
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'settings.json'));
    await file.writeAsString('''
{
  "outputPath": "",
  "diabloIV": {"enabled": true, "sourcePath": "auto"},
  "guildWars2": {"enabled": true, "sourcePath": "/legacy/gw2"},
  "hytale": {"enabled": true, "sourcePath": "auto", "downloadCovers": true},
  "minecraft": {"enabled": true, "sourcePath": "/legacy/minecraft"},
  "steam": {"enabled": true, "userdataPath": "auto"},
  "folderGrants": {
    "provider.diabloIV": {
      "platform": "macos",
      "path": "/legacy/diablo",
      "access": "readOnly",
      "bookmark": "legacy-bookmark"
    }
  }
}
''');

    final settings = await ConfigStore(filePath: file.path).load();

    expect(settings.battleNet.useCustomPath, isFalse);
    expect(settings.battleNet.sourcePath, isEmpty);
    expect(settings.guildWars2.useCustomPath, isTrue);
    expect(settings.guildWars2.sourcePath, '/legacy/gw2');
    expect(settings.hytale.useCustomPath, isFalse);
    expect(settings.hytale.sourcePath, isEmpty);
    expect(settings.hytale.downloadCovers, isTrue);
    expect(settings.minecraft.useCustomPath, isTrue);
    expect(settings.minecraft.sourcePath, '/legacy/minecraft');
    expect(settings.steam.useCustomPath, isFalse);
    expect(settings.steam.userdataPath, isEmpty);
    expect(settings.folderGrants['provider.diabloIV'], isNull);
    expect(
      settings.folderGrants['provider.battleNet']?.bookmark,
      'legacy-bookmark',
    );
  });
}
