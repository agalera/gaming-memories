import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/folder_access_service.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import '../services/video_metadata_service.dart';
import 'playstation_media.dart';
import 'screenshot_provider.dart';

class PlayStation5Provider
    with SingleFolderRequirement
    implements FolderBackedScreenshotProvider {
  const PlayStation5Provider({
    this.importer = const MediaImporter(),
    this.durationReader = const VideoMetadataService(),
  });

  final MediaImporter importer;
  final VideoDurationReader durationReader;

  static const id = 'ps5';
  static const platform = 'PlayStation 5';

  @override
  String get name => platform;

  @override
  String get folderGrantId => FolderGrantIds.playStation5;

  @override
  bool isEnabled(AppSettings settings) => settings.playStation5.enabled;

  @override
  ProviderFolderRequirement? folderRequirement(AppSettings settings) {
    final path = settings.playStation5.sourcePath.trim();
    return path.isEmpty
        ? null
        : ProviderFolderRequirement(
            id: folderGrantId,
            path: expandUserPath(path),
            automatic: false,
          );
  }

  @override
  AppSettings withFolderPath(AppSettings settings, String path) {
    return settings.copyWith(
      playStation5: settings.playStation5.copyWith(
        enabled: true,
        useCustomPath: true,
        sourcePath: path,
      ),
    );
  }

  @override
  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  }) async {
    if (!settings.playStation5.enabled) {
      return ImportResult.empty(name);
    }
    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    final sourcePath = settings.playStation5.sourcePath.trim();
    if (sourcePath.isEmpty) {
      throw const FileSystemException(
        'Choose a PlayStation 5 exported media folder in Settings.',
      );
    }
    final source = Directory(expandUserPath(sourcePath));
    if (!await source.exists()) {
      throw FileSystemException(
        'The selected PlayStation 5 media folder does not exist.',
        source.path,
      );
    }

    onProgress?.call(
      const ProviderProgress(message: 'Scanning PlayStation 5 media…'),
    );
    final files = await source
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && _isSupported(entity.path))
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));

    var imported = 0;
    var skipped = 0;
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      onProgress?.call(
        ProviderProgress(
          message: 'Importing PlayStation 5 media…',
          completed: index,
          total: files.length,
        ),
      );
      final destination = Directory(
        p.join(
          expandUserPath(outputPath),
          platform,
          p.basename(file.parent.path),
        ),
      );
      final timestamp = parsePlayStationTimestamp(
        p.basenameWithoutExtension(file.path),
      );
      bool copied;
      if (timestamp == null) {
        copied = await importer.copyWithName(
          file,
          Directory(p.join(destination.path, playStationUndatedFolder)),
          baseName:
              '$playStationUndatedPrefix${p.basenameWithoutExtension(file.path)}',
        );
      } else {
        var capturedAt = timestamp.capturedAt;
        if (p.extension(file.path).toLowerCase() == '.webm') {
          final duration = await durationReader.duration(file);
          if (duration != null) {
            capturedAt = capturedAt.subtract(duration);
          }
        }
        copied = await importer.copyAtDate(file, destination, capturedAt);
      }
      if (copied) {
        imported++;
      } else {
        skipped++;
      }
    }

    onProgress?.call(
      ProviderProgress(
        message: 'Processed PlayStation 5 media.',
        completed: files.length,
        total: files.length,
      ),
    );
    return ImportResult(provider: name, imported: imported, skipped: skipped);
  }

  static bool _isSupported(String path) {
    if (p.basename(path).startsWith('.')) {
      return false;
    }
    return const {'.jpg', '.webm'}.contains(p.extension(path).toLowerCase());
  }
}
