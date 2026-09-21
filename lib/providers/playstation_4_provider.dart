import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/folder_access_service.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import 'playstation_media.dart';
import 'screenshot_provider.dart';

class PlayStation4Provider
    with SingleFolderRequirement
    implements FolderBackedScreenshotProvider {
  const PlayStation4Provider({this.importer = const MediaImporter()});

  final MediaImporter importer;

  static const id = 'ps4';
  static const platform = 'PlayStation 4';

  @override
  String get name => platform;

  @override
  String get folderGrantId => FolderGrantIds.playStation4;

  @override
  bool isEnabled(AppSettings settings) => settings.playStation4.enabled;

  @override
  ProviderFolderRequirement? folderRequirement(AppSettings settings) {
    final path = settings.playStation4.sourcePath.trim();
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
      playStation4: settings.playStation4.copyWith(
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
    if (!settings.playStation4.enabled) {
      return ImportResult.empty(name);
    }
    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    final sourcePath = settings.playStation4.sourcePath.trim();
    if (sourcePath.isEmpty) {
      throw const FileSystemException(
        'Choose a PlayStation 4 exported media folder in Settings.',
      );
    }
    final source = Directory(expandUserPath(sourcePath));
    if (!await source.exists()) {
      throw FileSystemException(
        'The selected PlayStation 4 media folder does not exist.',
        source.path,
      );
    }

    onProgress?.call(
      const ProviderProgress(message: 'Scanning PlayStation 4 media…'),
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
          message: 'Importing PlayStation 4 media…',
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
      final extension = p.extension(file.path).toLowerCase();
      bool copied;
      if (extension == '.jpg') {
        copied = await importer.copyByModifiedDate(file, destination);
      } else {
        final timestamp = parsePlayStationTimestamp(
          p.basenameWithoutExtension(file.path),
        );
        copied = timestamp == null
            ? await importer.copyWithName(
                file,
                Directory(p.join(destination.path, playStationUndatedFolder)),
                baseName:
                    '$playStationUndatedPrefix${p.basenameWithoutExtension(file.path)}',
              )
            : await importer.copyAtDate(
                file,
                destination,
                timestamp.capturedAt,
              );
      }
      if (copied) {
        imported++;
      } else {
        skipped++;
      }
    }

    onProgress?.call(
      ProviderProgress(
        message: 'Processed PlayStation 4 media.',
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
    return const {'.jpg', '.mp4'}.contains(p.extension(path).toLowerCase());
  }
}
