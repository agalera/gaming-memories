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
      diabloIV: ProviderSettings(
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
    expect(actual.diabloIV.enabled, isTrue);
    expect(actual.diabloIV.useCustomPath, isTrue);
    expect(actual.diabloIV.sourcePath, expected.diabloIV.sourcePath);
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
    expect(json['version'], 7);
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
  "steam": {"enabled": true, "userdataPath": "auto"}
}
''');

    final settings = await ConfigStore(filePath: file.path).load();

    expect(settings.diabloIV.useCustomPath, isFalse);
    expect(settings.diabloIV.sourcePath, isEmpty);
    expect(settings.guildWars2.useCustomPath, isTrue);
    expect(settings.guildWars2.sourcePath, '/legacy/gw2');
    expect(settings.hytale.useCustomPath, isFalse);
    expect(settings.hytale.sourcePath, isEmpty);
    expect(settings.hytale.downloadCovers, isTrue);
    expect(settings.steam.useCustomPath, isFalse);
    expect(settings.steam.userdataPath, isEmpty);
  });
}
