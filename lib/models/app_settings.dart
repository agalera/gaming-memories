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

class ProviderSettings {
  const ProviderSettings({
    required this.enabled,
    required this.useCustomPath,
    required this.sourcePath,
    this.downloadCovers = false,
  });

  const ProviderSettings.disabled()
    : enabled = false,
      useCustomPath = false,
      sourcePath = '',
      downloadCovers = false;

  final bool enabled;
  final bool useCustomPath;
  final String sourcePath;
  final bool downloadCovers;

  ProviderSettings copyWith({
    bool? enabled,
    bool? useCustomPath,
    String? sourcePath,
    bool? downloadCovers,
  }) {
    return ProviderSettings(
      enabled: enabled ?? this.enabled,
      useCustomPath: useCustomPath ?? this.useCustomPath,
      sourcePath: sourcePath ?? this.sourcePath,
      downloadCovers: downloadCovers ?? this.downloadCovers,
    );
  }

  factory ProviderSettings.fromJson(Map<String, Object?> json) {
    final storedPath = json['sourcePath'] as String? ?? '';
    final hasLegacyCustomPath =
        storedPath.trim().isNotEmpty && storedPath.trim() != 'auto';

    return ProviderSettings(
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

class AppSettings {
  const AppSettings({
    required this.outputPath,
    required this.diabloIV,
    this.guildWars2 = const ProviderSettings.disabled(),
    this.hytale = const ProviderSettings.disabled(),
    this.minecraft = const ProviderSettings.disabled(),
    this.steam = const SteamSettings.disabled(),
    this.themeMode = AppThemeMode.system,
    this.folderGrants = const {},
  });

  const AppSettings.defaults()
    : outputPath = '',
      diabloIV = const ProviderSettings.disabled(),
      guildWars2 = const ProviderSettings.disabled(),
      hytale = const ProviderSettings.disabled(),
      minecraft = const ProviderSettings.disabled(),
      steam = const SteamSettings.disabled(),
      themeMode = AppThemeMode.system,
      folderGrants = const {};

  final String outputPath;
  final ProviderSettings diabloIV;
  final ProviderSettings guildWars2;
  final ProviderSettings hytale;
  final ProviderSettings minecraft;
  final SteamSettings steam;
  final AppThemeMode themeMode;
  final Map<String, FolderGrant> folderGrants;

  AppSettings copyWith({
    String? outputPath,
    ProviderSettings? diabloIV,
    ProviderSettings? guildWars2,
    ProviderSettings? hytale,
    ProviderSettings? minecraft,
    SteamSettings? steam,
    AppThemeMode? themeMode,
    Map<String, FolderGrant>? folderGrants,
  }) {
    return AppSettings(
      outputPath: outputPath ?? this.outputPath,
      diabloIV: diabloIV ?? this.diabloIV,
      guildWars2: guildWars2 ?? this.guildWars2,
      hytale: hytale ?? this.hytale,
      minecraft: minecraft ?? this.minecraft,
      steam: steam ?? this.steam,
      themeMode: themeMode ?? this.themeMode,
      folderGrants: folderGrants ?? this.folderGrants,
    );
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final providerJson = json['diabloIV'];
    final guildWars2Json = json['guildWars2'];
    final hytaleJson = json['hytale'];
    final minecraftJson = json['minecraft'];
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

    return AppSettings(
      outputPath: json['outputPath'] as String? ?? '',
      diabloIV: providerJson is Map<String, Object?>
          ? ProviderSettings.fromJson(providerJson)
          : const ProviderSettings.disabled(),
      guildWars2: guildWars2Json is Map<String, Object?>
          ? ProviderSettings.fromJson(guildWars2Json)
          : const ProviderSettings.disabled(),
      hytale: hytaleJson is Map<String, Object?>
          ? ProviderSettings.fromJson(hytaleJson)
          : const ProviderSettings.disabled(),
      minecraft: minecraftJson is Map<String, Object?>
          ? ProviderSettings.fromJson(minecraftJson)
          : const ProviderSettings.disabled(),
      steam: steamJson is Map<String, Object?>
          ? SteamSettings.fromJson(steamJson)
          : const SteamSettings.disabled(),
      themeMode: AppThemeMode.fromJson(json['themeMode']),
      folderGrants: Map.unmodifiable(grants),
    );
  }

  Map<String, Object?> toJson() => {
    'version': 8,
    'outputPath': outputPath,
    'themeMode': themeMode.name,
    'diabloIV': diabloIV.toJson(),
    'guildWars2': guildWars2.toJson(),
    'hytale': hytale.toJson(),
    'minecraft': minecraft.toJson(),
    'steam': steam.toJson(),
    'folderGrants': {
      for (final entry in folderGrants.entries) entry.key: entry.value.toJson(),
    },
  };
}
