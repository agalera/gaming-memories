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
      battleNet: BattleNetSettings(
        enabled: true,
        games: {
          'wow_retail': SourceSettings(
            enabled: true,
            useCustomPath: true,
            sourcePath: '/wow',
          ),
        },
      ),
      guildWars2: SourceSettings(
        enabled: true,
        useCustomPath: true,
        sourcePath: '/guild-wars-2',
      ),
      hytale: SourceSettings(
        enabled: true,
        useCustomPath: false,
        sourcePath: '/Users/alice/Pictures/Hytale Screenshots',
        downloadCovers: true,
      ),
      minecraft: SourceSettings(
        enabled: true,
        useCustomPath: true,
        sourcePath: '/minecraft/screenshots',
      ),
      nintendoSwitch: NintendoSwitchSettings(
        enabled: true,
        useCustomPath: true,
        sourcePath: '/switch-album',
        ignoredFolders: ['Otra carpeta'],
      ),
      nintendoSwitch2: NintendoSwitchSettings(
        enabled: true,
        useCustomPath: true,
        sourcePath: '/switch-2-album',
        ignoredFolders: ['Other folder', 'News'],
      ),
      playStation4: SourceSettings(
        enabled: true,
        useCustomPath: true,
        sourcePath: '/playstation-4',
      ),
      playStation5: SourceSettings(
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
    expect(actual.battleNet.game('wow_retail').useCustomPath, isTrue);
    expect(actual.battleNet.game('wow_retail').sourcePath, '/wow');
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
    expect(actual.nintendoSwitch.enabled, isTrue);
    expect(actual.nintendoSwitch.useCustomPath, isTrue);
    expect(actual.nintendoSwitch.sourcePath, '/switch-album');
    expect(actual.nintendoSwitch.ignoredFolders, ['Otra carpeta']);
    expect(actual.nintendoSwitch2.enabled, isTrue);
    expect(actual.nintendoSwitch2.useCustomPath, isTrue);
    expect(actual.nintendoSwitch2.sourcePath, '/switch-2-album');
    expect(actual.nintendoSwitch2.ignoredFolders, ['Other folder', 'News']);
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
    expect(json['version'], 14);
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
  "nintendoSwitch": {"enabled": true, "sourcePath": "auto"},
  "nintendoSwitch2": {"enabled": true, "sourcePath": "auto"},
  "steam": {"enabled": true, "userdataPath": "auto"},
  "folderGrants": {
    "source.diabloIV": {
      "platform": "macos",
      "path": "/legacy/diablo",
      "access": "readOnly",
      "bookmark": "legacy-bookmark"
    }
  }
}
''');

    final settings = await ConfigStore(filePath: file.path).load();

    // A settings file from before the split keeps only the master switch:
    // its single path pointed at a games root, not at any one game.
    expect(settings.battleNet.games, isEmpty);
    expect(settings.battleNet.game('wow_retail').enabled, isTrue);
    expect(settings.battleNet.game('wow_retail').useCustomPath, isFalse);
    expect(settings.guildWars2.useCustomPath, isTrue);
    expect(settings.guildWars2.sourcePath, '/legacy/gw2');
    expect(settings.hytale.useCustomPath, isFalse);
    expect(settings.hytale.sourcePath, isEmpty);
    expect(settings.hytale.downloadCovers, isTrue);
    expect(settings.minecraft.useCustomPath, isTrue);
    expect(settings.minecraft.sourcePath, '/legacy/minecraft');
    expect(settings.nintendoSwitch.useCustomPath, isFalse);
    expect(settings.nintendoSwitch.sourcePath, isEmpty);
    expect(settings.nintendoSwitch2.useCustomPath, isFalse);
    expect(settings.nintendoSwitch2.sourcePath, isEmpty);
    expect(
      settings.nintendoSwitch2.ignoredFolders,
      NintendoSwitchSettings.defaultIgnoredFolders,
    );
    expect(settings.steam.useCustomPath, isFalse);
    expect(settings.steam.userdataPath, isEmpty);
    expect(settings.folderGrants['source.diabloIV'], isNull);
    expect(
      settings.folderGrants['source.battleNet']?.bookmark,
      'legacy-bookmark',
    );
  });

  test('defaults a settings file with no Nintendo Switch section', () async {
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'settings.json'));
    await file.writeAsString('{"outputPath": "/screenshots"}');

    final settings = await ConfigStore(filePath: file.path).load();

    expect(settings.nintendoSwitch.enabled, isFalse);
    expect(
      settings.nintendoSwitch.ignoredFolders,
      NintendoSwitchSettings.defaultIgnoredFolders,
    );
  });

  test('preserves an explicitly empty console ignored folder list', () {
    final settings = NintendoSwitchSettings.fromJson({
      'ignoredFolders': <String>[],
    });

    expect(settings.ignoredFolders, isEmpty);
  });

  test(
    'a settings file from before Publish loads with it turned off',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gaming-memories-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(p.join(directory.path, 'settings.json'));
      await file.writeAsString('{"outputPath": "/screenshots"}');

      final actual = await ConfigStore(filePath: file.path).load();

      expect(actual.publish.enabled, isFalse);
      expect(actual.publish.transport, PublishTransportKind.auto);
      expect(actual.publish.target.port, 22);
      expect(actual.publish.target.fileMode, '644');
      expect(actual.publish.target.directoryMode, '755');
      expect(actual.publish.target.deleteRemoved, isTrue);
      expect(
        actual.publish.target.credential,
        PublishCredentialKind.automaticKey,
      );
      expect(actual.publish.excluded, isEmpty);
    },
  );

  test(
    'a settings file from before the credential choice keeps its key',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gaming-memories-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final withKey = File(p.join(directory.path, 'with-key.json'));
      await withKey.writeAsString(
        '{"publish": {"target": {"keyPath": "/home/me/.ssh/id_ed25519"}}}',
      );
      final withoutKey = File(p.join(directory.path, 'without-key.json'));
      await withoutKey.writeAsString('{"publish": {"target": {}}}');

      final named = await ConfigStore(filePath: withKey.path).load();
      final unnamed = await ConfigStore(filePath: withoutKey.path).load();

      // A file that named a key meant that key, and one that named none meant
      // whatever the system offers.
      expect(named.publish.target.credential, PublishCredentialKind.manualKey);
      expect(named.publish.target.keyPath, '/home/me/.ssh/id_ed25519');
      expect(
        unnamed.publish.target.credential,
        PublishCredentialKind.automaticKey,
      );
    },
  );

  test('keeps the publish settings across a save and a load', () async {
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );

    const settings = AppSettings(
      outputPath: '/screenshots',
      publish: PublishSettings(
        enabled: true,
        transport: PublishTransportKind.sftp,
        site: PublishSiteSettings(
          title: 'Games Screenshots',
          author: '@fmartingr',
          url: 'https://screenshots.example.com',
          footerText: 'Be wary of spoilers!',
        ),
        target: PublishTargetSettings(
          host: 'example.com',
          port: 2222,
          username: 'deploy',
          remotePath: '/srv/site',
          credential: PublishCredentialKind.manualKey,
          keyPath: '/home/me/.ssh/id_ed25519',
          fileMode: '600',
          directoryMode: '700',
          deleteRemoved: false,
        ),
        excluded: ['Steam/Private'],
      ),
    );

    await store.save(settings);
    final actual = await store.load();

    expect(actual.publish.enabled, isTrue);
    expect(actual.publish.transport, PublishTransportKind.sftp);
    expect(actual.publish.site.title, 'Games Screenshots');
    expect(actual.publish.site.url, 'https://screenshots.example.com');
    expect(actual.publish.site.footerText, 'Be wary of spoilers!');
    expect(actual.publish.target.host, 'example.com');
    expect(actual.publish.target.port, 2222);
    expect(actual.publish.target.username, 'deploy');
    expect(actual.publish.target.remotePath, '/srv/site');
    expect(actual.publish.target.credential, PublishCredentialKind.manualKey);
    expect(actual.publish.target.keyPath, '/home/me/.ssh/id_ed25519');
    expect(actual.publish.target.fileMode, '600');
    expect(actual.publish.target.directoryMode, '700');
    expect(actual.publish.target.deleteRemoved, isFalse);
    expect(actual.publish.excluded, ['Steam/Private']);
  });

  test('no passphrase is ever written to the settings file', () async {
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );

    await store.save(
      const AppSettings(
        outputPath: '/screenshots',
        publish: PublishSettings(
          enabled: true,
          target: PublishTargetSettings(
            host: 'example.com',
            port: 22,
            username: 'deploy',
            remotePath: '/srv/site',
            keyPath: '/home/me/.ssh/id_ed25519',
            fileMode: '644',
            directoryMode: '755',
            deleteRemoved: true,
          ),
        ),
      ),
    );

    final written = await File(store.filePath).readAsString();
    expect(written, contains('/home/me/.ssh/id_ed25519'));
    expect(written.toLowerCase(), isNot(contains('passphrase')));
    expect(written.toLowerCase(), isNot(contains('"password"')));
  });
}
