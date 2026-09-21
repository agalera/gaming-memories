import '../models/app_settings.dart';

typedef ProgressCallback = void Function(ProviderProgress progress);

class ProviderProgress {
  const ProviderProgress({required this.message, this.completed, this.total});

  final String message;
  final int? completed;
  final int? total;

  double? get value {
    final maximum = total;
    final current = completed;
    if (maximum == null || current == null || maximum <= 0) {
      return null;
    }
    return (current / maximum).clamp(0, 1);
  }
}

class ImportResult {
  const ImportResult({
    required this.provider,
    required this.imported,
    required this.skipped,
    this.warning,
  });

  const ImportResult.empty(this.provider)
    : imported = 0,
      skipped = 0,
      warning = null;

  const ImportResult.warning(this.provider, this.warning)
    : imported = 0,
      skipped = 0;

  final String provider;
  final int imported;
  final int skipped;
  final String? warning;
}

class ProviderFolderRequirement {
  const ProviderFolderRequirement({
    required this.id,
    required this.path,
    required this.automatic,
    this.description,
  });

  final String id;
  final String path;
  final bool automatic;

  /// What this folder holds, for the settings row. Providers that need several
  /// folders set it, because one sentence cannot describe folders that differ
  /// in kind.
  final String? description;
}

abstract interface class ScreenshotProvider {
  String get name;

  bool isEnabled(AppSettings settings);

  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  });
}

abstract interface class ProviderConfigurationValidator {
  Future<String?> configurationError(AppSettings settings);
}

abstract interface class FolderBackedScreenshotProvider
    implements ScreenshotProvider {
  String get folderGrantId;

  /// The provider's primary folder, used wherever a single folder has to stand
  /// for the provider. Providers that need several folders return the first of
  /// [folderRequirements] here.
  ProviderFolderRequirement? folderRequirement(AppSettings settings);

  /// Every folder the provider needs access to.
  List<ProviderFolderRequirement> folderRequirements(AppSettings settings);

  AppSettings withFolderPath(AppSettings settings, String path);
}

/// Implements [FolderBackedScreenshotProvider.folderRequirements] for the
/// providers whose screenshots all live under one folder.
mixin SingleFolderRequirement implements FolderBackedScreenshotProvider {
  @override
  List<ProviderFolderRequirement> folderRequirements(AppSettings settings) {
    final requirement = folderRequirement(settings);
    return requirement == null ? const [] : [requirement];
  }
}
