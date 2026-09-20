import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import '../services/folder_access_service.dart';
import '../services/provider_paths.dart';
import 'screenshot_provider.dart';

class DiabloIVProvider implements FolderBackedScreenshotProvider {
  const DiabloIVProvider({this.importer = const MediaImporter()});

  final MediaImporter importer;

  static const id = 'diablo_4';
  static const gameName = 'Diablo IV';
  static const platform = 'PC';
  static const _extensions = {'.jpg', '.jpeg', '.png'};

  @override
  String get name => gameName;

  @override
  String get folderGrantId => FolderGrantIds.diabloIV;

  @override
  bool isEnabled(AppSettings settings) => settings.diabloIV.enabled;

  @override
  ProviderFolderRequirement? folderRequirement(AppSettings settings) {
    final provider = settings.diabloIV;
    if (provider.useCustomPath) {
      final path = provider.sourcePath.trim();
      return path.isEmpty
          ? null
          : ProviderFolderRequirement(
              id: folderGrantId,
              path: expandUserPath(path),
              automatic: false,
            );
    }
    final paths = ProviderPaths.diabloIVScreenshots();
    return paths.isEmpty
        ? null
        : ProviderFolderRequirement(
            id: folderGrantId,
            path: paths.first,
            automatic: true,
          );
  }

  @override
  AppSettings withFolderPath(AppSettings settings, String path) {
    return settings.copyWith(
      diabloIV: settings.diabloIV.copyWith(
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
    if (!settings.diabloIV.enabled) {
      return ImportResult.empty(name);
    }

    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    final sourceDirectories = _sourceDirectories(settings.diabloIV);
    if (sourceDirectories.isEmpty) {
      if (!settings.diabloIV.useCustomPath) {
        return const ImportResult.warning(
          gameName,
          'Diablo IV was skipped because no installation was found.',
        );
      }
      throw const FileSystemException(
        'Choose a Diablo IV screenshot folder in Settings.',
      );
    }

    final existingSourceDirectories = <Directory>[];
    for (final sourceDirectory in sourceDirectories) {
      if (await sourceDirectory.exists()) {
        existingSourceDirectories.add(sourceDirectory);
      }
    }
    if (existingSourceDirectories.isEmpty) {
      if (!settings.diabloIV.useCustomPath) {
        return const ImportResult.warning(
          gameName,
          'Diablo IV was skipped because no installation was found.',
        );
      }
      throw FileSystemException(
        'The selected Diablo IV screenshot folder does not exist.',
        settings.diabloIV.sourcePath,
      );
    }

    final destination = Directory(
      p.join(expandUserPath(outputPath), platform, gameName),
    );
    await destination.create(recursive: true);

    onProgress?.call(
      const ProviderProgress(message: 'Scanning Diablo IV screenshots…'),
    );
    final files = <File>[];

    for (final sourceDirectory in existingSourceDirectories) {
      final sourceFiles = await sourceDirectory
          .list(followLinks: false)
          .where((entity) => entity is File && _isScreenshot(entity.path))
          .cast<File>()
          .toList();
      files.addAll(sourceFiles);
    }
    files.sort((left, right) => left.path.compareTo(right.path));

    var imported = 0;
    var skipped = 0;
    for (var index = 0; index < files.length; index++) {
      onProgress?.call(
        ProviderProgress(
          message: 'Importing Diablo IV screenshots…',
          completed: index,
          total: files.length,
        ),
      );
      final copied = await importer.copyByModifiedDate(
        files[index],
        destination,
      );
      if (copied) {
        imported++;
      } else {
        skipped++;
      }
    }
    onProgress?.call(
      ProviderProgress(
        message: 'Processed Diablo IV screenshots.',
        completed: files.length,
        total: files.length,
      ),
    );

    return ImportResult(provider: name, imported: imported, skipped: skipped);
  }

  List<Directory> _sourceDirectories(ProviderSettings settings) {
    final path = settings.sourcePath.trim();
    if (settings.useCustomPath) {
      if (path.isEmpty) {
        return const [];
      }
      return [Directory(expandUserPath(path))];
    }

    return ProviderPaths.diabloIVScreenshots().map(Directory.new).toList();
  }

  bool _isScreenshot(String path) {
    return _extensions.contains(p.extension(path).toLowerCase());
  }
}
