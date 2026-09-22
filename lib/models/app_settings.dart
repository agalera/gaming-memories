enum FolderGrantAccess {
  readOnly,
  readWrite;

  factory FolderGrantAccess.fromJson(Object? value) {
    return value == readWrite.name ? readWrite : readOnly;
  }
}

class FolderGrant {
  const FolderGrant({
    required this.platform,
    required this.path,
    required this.access,
    required this.bookmark,
  });

  final String platform;
  final String path;
  final FolderGrantAccess access;
  final String bookmark;

  FolderGrant copyWith({
    String? platform,
    String? path,
    FolderGrantAccess? access,
    String? bookmark,
  }) {
    return FolderGrant(
      platform: platform ?? this.platform,
      path: path ?? this.path,
      access: access ?? this.access,
      bookmark: bookmark ?? this.bookmark,
    );
  }

  factory FolderGrant.fromJson(Map<String, Object?> json) {
    return FolderGrant(
      platform: json['platform'] as String? ?? '',
      path: json['path'] as String? ?? '',
      access: FolderGrantAccess.fromJson(json['access']),
      bookmark: json['bookmark'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'platform': platform,
    'path': path,
    'access': access.name,
    'bookmark': bookmark,
  };
}

enum AppThemeMode {
  system,
  light,
  dark;

  factory AppThemeMode.fromJson(Object? value) {
    for (final mode in values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return system;
  }
}

class SourceSettings {
  const SourceSettings({
    required this.enabled,
    required this.useCustomPath,
    required this.sourcePath,
    this.downloadCovers = false,
  });

  const SourceSettings.disabled()
    : enabled = false,
      useCustomPath = false,
      sourcePath = '',
      downloadCovers = false;

  final bool enabled;
  final bool useCustomPath;
  final String sourcePath;
  final bool downloadCovers;

  SourceSettings copyWith({
    bool? enabled,
    bool? useCustomPath,
    String? sourcePath,
    bool? downloadCovers,
  }) {
    return SourceSettings(
      enabled: enabled ?? this.enabled,
      useCustomPath: useCustomPath ?? this.useCustomPath,
      sourcePath: sourcePath ?? this.sourcePath,
      downloadCovers: downloadCovers ?? this.downloadCovers,
    );
  }

  factory SourceSettings.fromJson(Map<String, Object?> json) {
    final storedPath = json['sourcePath'] as String? ?? '';
    final hasLegacyCustomPath =
        storedPath.trim().isNotEmpty && storedPath.trim() != 'auto';

    return SourceSettings(
      enabled: json['enabled'] as bool? ?? false,
      useCustomPath: json['useCustomPath'] as bool? ?? hasLegacyCustomPath,
      sourcePath: hasLegacyCustomPath ? storedPath : '',
      downloadCovers: json['downloadCovers'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'useCustomPath': useCustomPath,
    'sourcePath': sourcePath,
    'downloadCovers': downloadCovers,
  };
}

class SteamSettings {
  const SteamSettings({
    required this.enabled,
    required this.useCustomPath,
    required this.userdataPath,
    required this.onlineGallery,
    required this.userId,
    required this.apiKey,
    required this.downloadCovers,
    required this.ignoredGames,
    required this.customGames,
  });

  const SteamSettings.disabled()
    : enabled = false,
      useCustomPath = false,
      userdataPath = '',
      onlineGallery = false,
      userId = '',
      apiKey = '',
      downloadCovers = false,
      ignoredGames = const [],
      customGames = const {};

  final bool enabled;
  final bool useCustomPath;
  final String userdataPath;
  final bool onlineGallery;
  final String userId;
  final String apiKey;
  final bool downloadCovers;
  final List<String> ignoredGames;
  final Map<String, String> customGames;

  SteamSettings copyWith({
    bool? enabled,
    bool? useCustomPath,
    String? userdataPath,
    bool? onlineGallery,
    String? userId,
    String? apiKey,
    bool? downloadCovers,
    List<String>? ignoredGames,
    Map<String, String>? customGames,
  }) {
    return SteamSettings(
      enabled: enabled ?? this.enabled,
      useCustomPath: useCustomPath ?? this.useCustomPath,
      userdataPath: userdataPath ?? this.userdataPath,
      onlineGallery: onlineGallery ?? this.onlineGallery,
      userId: userId ?? this.userId,
      apiKey: apiKey ?? this.apiKey,
      downloadCovers: downloadCovers ?? this.downloadCovers,
      ignoredGames: ignoredGames ?? this.ignoredGames,
      customGames: customGames ?? this.customGames,
    );
  }

  factory SteamSettings.fromJson(Map<String, Object?> json) {
    final ignored = json['ignoredGames'];
    final custom = json['customGames'];
    final storedPath = json['userdataPath'] as String? ?? '';
    final hasLegacyCustomPath =
        storedPath.trim().isNotEmpty && storedPath.trim() != 'auto';

    return SteamSettings(
      enabled: json['enabled'] as bool? ?? false,
      useCustomPath: json['useCustomPath'] as bool? ?? hasLegacyCustomPath,
      userdataPath: hasLegacyCustomPath ? storedPath : '',
      onlineGallery: json['onlineGallery'] as bool? ?? false,
      userId: json['userId'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      downloadCovers: json['downloadCovers'] as bool? ?? false,
      ignoredGames: ignored is List
          ? ignored.whereType<String>().toList(growable: false)
          : const [],
      customGames: custom is Map
          ? custom.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'useCustomPath': useCustomPath,
    'userdataPath': userdataPath,
    'onlineGallery': onlineGallery,
    'userId': userId,
    'apiKey': apiKey,
    'downloadCovers': downloadCovers,
    'ignoredGames': ignoredGames,
    'customGames': customGames,
  };
}

class NintendoSwitchSettings {
  const NintendoSwitchSettings({
    required this.enabled,
    required this.useCustomPath,
    required this.sourcePath,
    required this.ignoredFolders,
  });

  const NintendoSwitchSettings.disabled()
    : enabled = false,
      useCustomPath = false,
      sourcePath = '',
      ignoredFolders = defaultIgnoredFolders;

  static const defaultIgnoredFolders = ['Otra carpeta'];

  final bool enabled;
  final bool useCustomPath;
  final String sourcePath;
  final List<String> ignoredFolders;

  NintendoSwitchSettings copyWith({
    bool? enabled,
    bool? useCustomPath,
    String? sourcePath,
    List<String>? ignoredFolders,
  }) {
    return NintendoSwitchSettings(
      enabled: enabled ?? this.enabled,
      useCustomPath: useCustomPath ?? this.useCustomPath,
      sourcePath: sourcePath ?? this.sourcePath,
      ignoredFolders: ignoredFolders ?? this.ignoredFolders,
    );
  }

  factory NintendoSwitchSettings.fromJson(Map<String, Object?> json) {
    final storedPath = json['sourcePath'] as String? ?? '';
    final hasLegacyCustomPath =
        storedPath.trim().isNotEmpty && storedPath.trim() != 'auto';
    final ignored = json['ignoredFolders'];

    return NintendoSwitchSettings(
      enabled: json['enabled'] as bool? ?? false,
      useCustomPath: json['useCustomPath'] as bool? ?? hasLegacyCustomPath,
      sourcePath: hasLegacyCustomPath ? storedPath : '',
      ignoredFolders: ignored is List
          ? ignored.whereType<String>().toList(growable: false)
          : defaultIgnoredFolders,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'useCustomPath': useCustomPath,
    'sourcePath': sourcePath,
    'ignoredFolders': ignoredFolders,
  };
}

/// Battle.net is one source over several games, so it carries a master
/// switch plus a setting per game, keyed by [BattleNetGame.id].
class BattleNetSettings {
  const BattleNetSettings({required this.enabled, this.games = const {}});

  const BattleNetSettings.disabled() : enabled = false, games = const {};

  final bool enabled;
  final Map<String, SourceSettings> games;

  /// A game with nothing stored is on: the source should work as soon as
  /// the user enables Battle.net, and a game whose folder is not there is
  /// skipped anyway.
  SourceSettings game(String id) =>
      games[id] ??
      const SourceSettings(enabled: true, useCustomPath: false, sourcePath: '');

  BattleNetSettings copyWith({
    bool? enabled,
    Map<String, SourceSettings>? games,
  }) {
    return BattleNetSettings(
      enabled: enabled ?? this.enabled,
      games: games ?? this.games,
    );
  }

  BattleNetSettings withGame(String id, SourceSettings value) {
    return copyWith(games: Map.unmodifiable({...games, id: value}));
  }

  factory BattleNetSettings.fromJson(Map<String, Object?> json) {
    final gamesJson = json['games'];
    final games = <String, SourceSettings>{};
    if (gamesJson is Map) {
      for (final entry in gamesJson.entries) {
        final value = entry.value;
        if (value is Map) {
          games[entry.key.toString()] = SourceSettings.fromJson(
            value.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    }
    return BattleNetSettings(
      enabled: json['enabled'] as bool? ?? false,
      games: Map.unmodifiable(games),
    );
  }

  /// Reads a settings file from before the source was split per game. Only
  /// the master switch survives: the old path pointed at one games root, and
  /// there is no way to tell which game it was for.
  factory BattleNetSettings.fromLegacyJson(Map<String, Object?> json) {
    return BattleNetSettings(enabled: json['enabled'] as bool? ?? false);
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'games': {
      for (final entry in games.entries) entry.key: entry.value.toJson(),
    },
  };
}

class AppSettings {
  const AppSettings({
    required this.outputPath,
    this.battleNet = const BattleNetSettings.disabled(),
    this.guildWars2 = const SourceSettings.disabled(),
    this.hytale = const SourceSettings.disabled(),
    this.minecraft = const SourceSettings.disabled(),
    this.nintendoSwitch = const NintendoSwitchSettings.disabled(),
    this.nintendoSwitch2 = const NintendoSwitchSettings.disabled(),
    this.playStation4 = const SourceSettings.disabled(),
    this.playStation5 = const SourceSettings.disabled(),
    this.steam = const SteamSettings.disabled(),
    this.themeMode = AppThemeMode.system,
    this.folderGrants = const {},
  });

  const AppSettings.defaults()
    : outputPath = '',
      battleNet = const BattleNetSettings.disabled(),
      guildWars2 = const SourceSettings.disabled(),
      hytale = const SourceSettings.disabled(),
      minecraft = const SourceSettings.disabled(),
      nintendoSwitch = const NintendoSwitchSettings.disabled(),
      nintendoSwitch2 = const NintendoSwitchSettings.disabled(),
      playStation4 = const SourceSettings.disabled(),
      playStation5 = const SourceSettings.disabled(),
      steam = const SteamSettings.disabled(),
      themeMode = AppThemeMode.system,
      folderGrants = const {};

  final String outputPath;
  final BattleNetSettings battleNet;
  final SourceSettings guildWars2;
  final SourceSettings hytale;
  final SourceSettings minecraft;
  final NintendoSwitchSettings nintendoSwitch;
  final NintendoSwitchSettings nintendoSwitch2;
  final SourceSettings playStation4;
  final SourceSettings playStation5;
  final SteamSettings steam;
  final AppThemeMode themeMode;
  final Map<String, FolderGrant> folderGrants;

  AppSettings copyWith({
    String? outputPath,
    BattleNetSettings? battleNet,
    SourceSettings? guildWars2,
    SourceSettings? hytale,
    SourceSettings? minecraft,
    NintendoSwitchSettings? nintendoSwitch,
    NintendoSwitchSettings? nintendoSwitch2,
    SourceSettings? playStation4,
    SourceSettings? playStation5,
    SteamSettings? steam,
    AppThemeMode? themeMode,
    Map<String, FolderGrant>? folderGrants,
  }) {
    return AppSettings(
      outputPath: outputPath ?? this.outputPath,
      battleNet: battleNet ?? this.battleNet,
      guildWars2: guildWars2 ?? this.guildWars2,
      hytale: hytale ?? this.hytale,
      minecraft: minecraft ?? this.minecraft,
      nintendoSwitch: nintendoSwitch ?? this.nintendoSwitch,
      nintendoSwitch2: nintendoSwitch2 ?? this.nintendoSwitch2,
      playStation4: playStation4 ?? this.playStation4,
      playStation5: playStation5 ?? this.playStation5,
      steam: steam ?? this.steam,
      themeMode: themeMode ?? this.themeMode,
      folderGrants: folderGrants ?? this.folderGrants,
    );
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final battleNetJson = json['battleNet'] ?? json['diabloIV'];
    final guildWars2Json = json['guildWars2'];
    final hytaleJson = json['hytale'];
    final minecraftJson = json['minecraft'];
    final nintendoSwitchJson = json['nintendoSwitch'];
    final nintendoSwitch2Json = json['nintendoSwitch2'];
    final playStation4Json = json['playStation4'];
    final playStation5Json = json['playStation5'];
    final steamJson = json['steam'];
    final grantsJson = json['folderGrants'];
    final grants = <String, FolderGrant>{};
    if (grantsJson is Map) {
      for (final entry in grantsJson.entries) {
        final value = entry.value;
        if (value is Map) {
          grants[entry.key.toString()] = FolderGrant.fromJson(
            value.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    }
    final legacyBattleNetGrant = grants.remove('source.diabloIV');
    if (legacyBattleNetGrant != null &&
        !grants.containsKey('source.battleNet')) {
      grants['source.battleNet'] = legacyBattleNetGrant;
    }

    return AppSettings(
      outputPath: json['outputPath'] as String? ?? '',
      battleNet: battleNetJson is! Map<String, Object?>
          ? const BattleNetSettings.disabled()
          : battleNetJson.containsKey('games')
          ? BattleNetSettings.fromJson(battleNetJson)
          : BattleNetSettings.fromLegacyJson(battleNetJson),
      guildWars2: guildWars2Json is Map<String, Object?>
          ? SourceSettings.fromJson(guildWars2Json)
          : const SourceSettings.disabled(),
      hytale: hytaleJson is Map<String, Object?>
          ? SourceSettings.fromJson(hytaleJson)
          : const SourceSettings.disabled(),
      minecraft: minecraftJson is Map<String, Object?>
          ? SourceSettings.fromJson(minecraftJson)
          : const SourceSettings.disabled(),
      nintendoSwitch: nintendoSwitchJson is Map<String, Object?>
          ? NintendoSwitchSettings.fromJson(nintendoSwitchJson)
          : const NintendoSwitchSettings.disabled(),
      nintendoSwitch2: nintendoSwitch2Json is Map<String, Object?>
          ? NintendoSwitchSettings.fromJson(nintendoSwitch2Json)
          : const NintendoSwitchSettings.disabled(),
      playStation4: playStation4Json is Map<String, Object?>
          ? SourceSettings.fromJson(playStation4Json)
          : const SourceSettings.disabled(),
      playStation5: playStation5Json is Map<String, Object?>
          ? SourceSettings.fromJson(playStation5Json)
          : const SourceSettings.disabled(),
      steam: steamJson is Map<String, Object?>
          ? SteamSettings.fromJson(steamJson)
          : const SteamSettings.disabled(),
      themeMode: AppThemeMode.fromJson(json['themeMode']),
      folderGrants: Map.unmodifiable(grants),
    );
  }

  Map<String, Object?> toJson() => {
    'version': 13,
    'outputPath': outputPath,
    'themeMode': themeMode.name,
    'battleNet': battleNet.toJson(),
    'guildWars2': guildWars2.toJson(),
    'hytale': hytale.toJson(),
    'minecraft': minecraft.toJson(),
    'nintendoSwitch': nintendoSwitch.toJson(),
    'nintendoSwitch2': nintendoSwitch2.toJson(),
    'playStation4': playStation4.toJson(),
    'playStation5': playStation5.toJson(),
    'steam': steam.toJson(),
    'folderGrants': {
      for (final entry in folderGrants.entries) entry.key: entry.value.toJson(),
    },
  };
}
