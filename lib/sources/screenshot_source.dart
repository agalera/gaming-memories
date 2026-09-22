import '../models/app_settings.dart';

typedef ProgressCallback = void Function(SourceProgress progress);

class SourceProgress {
  const SourceProgress({required this.message, this.completed, this.total});

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
    required this.source,
    required this.imported,
    required this.skipped,
    this.warning,
  });

  const ImportResult.empty(this.source)
    : imported = 0,
      skipped = 0,
      warning = null;

  const ImportResult.warning(this.source, this.warning)
    : imported = 0,
      skipped = 0;

  final String source;
  final int imported;
  final int skipped;
  final String? warning;
}

class SourceFolderRequirement {
  const SourceFolderRequirement({
    required this.id,
    required this.path,
    required this.automatic,
    this.description,
  });

  final String id;
  final String path;
  final bool automatic;

  /// What this folder holds, for the settings row. Sources that need several
  /// folders set it, because one sentence cannot describe folders that differ
  /// in kind.
  final String? description;
}

abstract interface class ScreenshotSource {
  String get name;

  bool isEnabled(AppSettings settings);

  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  });
}

abstract interface class SourceConfigurationValidator {
  Future<String?> configurationError(AppSettings settings);
}

abstract interface class FolderBackedScreenshotSource
    implements ScreenshotSource {
  String get folderGrantId;

  /// The source's primary folder, used wherever a single folder has to stand
  /// for the source. Sources that need several folders return the first of
  /// [folderRequirements] here.
  SourceFolderRequirement? folderRequirement(AppSettings settings);

  /// Every folder the source needs access to.
  List<SourceFolderRequirement> folderRequirements(AppSettings settings);

  AppSettings withFolderPath(AppSettings settings, String path);
}

/// Implements [FolderBackedScreenshotSource.folderRequirements] for the
/// sources whose screenshots all live under one folder.
mixin SingleFolderRequirement implements FolderBackedScreenshotSource {
  @override
  List<SourceFolderRequirement> folderRequirements(AppSettings settings) {
    final requirement = folderRequirement(settings);
    return requirement == null ? const [] : [requirement];
  }
}
