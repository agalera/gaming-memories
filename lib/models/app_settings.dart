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
  });

  const ProviderSettings.disabled()
    : enabled = false,
      useCustomPath = false,
      sourcePath = '';

  final bool enabled;
  final bool useCustomPath;
  final String sourcePath;

  ProviderSettings copyWith({
    bool? enabled,
    bool? useCustomPath,
    String? sourcePath,
  }) {
    return ProviderSettings(
      enabled: enabled ?? this.enabled,
      useCustomPath: useCustomPath ?? this.useCustomPath,
      sourcePath: sourcePath ?? this.sourcePath,
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
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'useCustomPath': useCustomPath,
    'sourcePath': sourcePath,
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
    this.steam = const SteamSettings.disabled(),
    this.themeMode = AppThemeMode.system,
  });

  const AppSettings.defaults()
    : outputPath = '',
      diabloIV = const ProviderSettings.disabled(),
      guildWars2 = const ProviderSettings.disabled(),
      steam = const SteamSettings.disabled(),
      themeMode = AppThemeMode.system;

  final String outputPath;
  final ProviderSettings diabloIV;
  final ProviderSettings guildWars2;
  final SteamSettings steam;
  final AppThemeMode themeMode;

  AppSettings copyWith({
    String? outputPath,
    ProviderSettings? diabloIV,
    ProviderSettings? guildWars2,
    SteamSettings? steam,
    AppThemeMode? themeMode,
  }) {
    return AppSettings(
      outputPath: outputPath ?? this.outputPath,
      diabloIV: diabloIV ?? this.diabloIV,
      guildWars2: guildWars2 ?? this.guildWars2,
      steam: steam ?? this.steam,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final providerJson = json['diabloIV'];
    final guildWars2Json = json['guildWars2'];
    final steamJson = json['steam'];

    return AppSettings(
      outputPath: json['outputPath'] as String? ?? '',
      diabloIV: providerJson is Map<String, Object?>
          ? ProviderSettings.fromJson(providerJson)
          : const ProviderSettings.disabled(),
      guildWars2: guildWars2Json is Map<String, Object?>
          ? ProviderSettings.fromJson(guildWars2Json)
          : const ProviderSettings.disabled(),
      steam: steamJson is Map<String, Object?>
          ? SteamSettings.fromJson(steamJson)
          : const SteamSettings.disabled(),
      themeMode: AppThemeMode.fromJson(json['themeMode']),
    );
  }

  Map<String, Object?> toJson() => {
    'version': 5,
    'outputPath': outputPath,
    'themeMode': themeMode.name,
    'diabloIV': diabloIV.toJson(),
    'guildWars2': guildWars2.toJson(),
    'steam': steam.toJson(),
  };
}
