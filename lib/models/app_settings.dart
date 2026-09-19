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

class AppSettings {
  const AppSettings({required this.outputPath, required this.diabloIV});

  const AppSettings.defaults()
    : outputPath = '',
      diabloIV = const ProviderSettings.disabled();

  final String outputPath;
  final ProviderSettings diabloIV;

  AppSettings copyWith({String? outputPath, ProviderSettings? diabloIV}) {
    return AppSettings(
      outputPath: outputPath ?? this.outputPath,
      diabloIV: diabloIV ?? this.diabloIV,
    );
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final providerJson = json['diabloIV'];

    return AppSettings(
      outputPath: json['outputPath'] as String? ?? '',
      diabloIV: providerJson is Map<String, Object?>
          ? ProviderSettings.fromJson(providerJson)
          : const ProviderSettings.disabled(),
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'outputPath': outputPath,
    'diabloIV': diabloIV.toJson(),
  };
}
