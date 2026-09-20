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
  });

  final String id;
  final String path;
  final bool automatic;
}

abstract interface class ScreenshotProvider {
  String get name;

  bool isEnabled(AppSettings settings);

  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  });
}

abstract interface class FolderBackedScreenshotProvider
    implements ScreenshotProvider {
  String get folderGrantId;

  ProviderFolderRequirement? folderRequirement(AppSettings settings);

  AppSettings withFolderPath(AppSettings settings, String path);
}
