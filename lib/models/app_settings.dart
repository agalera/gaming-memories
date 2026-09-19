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
  const ProviderSettings({required this.enabled, required this.sourcePath});

  const ProviderSettings.disabled() : enabled = false, sourcePath = '';

  final bool enabled;
  final String sourcePath;

  ProviderSettings copyWith({bool? enabled, String? sourcePath}) {
    return ProviderSettings(
      enabled: enabled ?? this.enabled,
      sourcePath: sourcePath ?? this.sourcePath,
    );
  }

  factory ProviderSettings.fromJson(Map<String, Object?> json) {
    return ProviderSettings(
      enabled: json['enabled'] as bool? ?? false,
      sourcePath: json['sourcePath'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'sourcePath': sourcePath,
  };
}

class SteamSettings {
  const SteamSettings({
    required this.enabled,
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
      userdataPath = 'auto',
      onlineGallery = false,
      userId = '',
      apiKey = '',
      downloadCovers = false,
      ignoredGames = const [],
      customGames = const {};

  final bool enabled;
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

    return SteamSettings(
      enabled: json['enabled'] as bool? ?? false,
      userdataPath: json['userdataPath'] as String? ?? 'auto',
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
    this.steam = const SteamSettings.disabled(),
    this.themeMode = AppThemeMode.system,
  });

  const AppSettings.defaults()
    : outputPath = '',
      diabloIV = const ProviderSettings.disabled(),
      steam = const SteamSettings.disabled(),
      themeMode = AppThemeMode.system;

  final String outputPath;
  final ProviderSettings diabloIV;
  final SteamSettings steam;
  final AppThemeMode themeMode;

  AppSettings copyWith({
    String? outputPath,
    ProviderSettings? diabloIV,
    SteamSettings? steam,
    AppThemeMode? themeMode,
  }) {
    return AppSettings(
      outputPath: outputPath ?? this.outputPath,
      diabloIV: diabloIV ?? this.diabloIV,
      steam: steam ?? this.steam,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final providerJson = json['diabloIV'];
    final steamJson = json['steam'];

    return AppSettings(
      outputPath: json['outputPath'] as String? ?? '',
      diabloIV: providerJson is Map<String, Object?>
          ? ProviderSettings.fromJson(providerJson)
          : const ProviderSettings.disabled(),
      steam: steamJson is Map<String, Object?>
          ? SteamSettings.fromJson(steamJson)
          : const SteamSettings.disabled(),
      themeMode: AppThemeMode.fromJson(json['themeMode']),
    );
  }

  Map<String, Object?> toJson() => {
    'version': 3,
    'outputPath': outputPath,
    'themeMode': themeMode.name,
    'diabloIV': diabloIV.toJson(),
    'steam': steam.toJson(),
  };
}
