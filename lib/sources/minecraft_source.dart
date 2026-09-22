import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/folder_access_service.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import '../services/source_paths.dart';
import 'screenshot_source.dart';

class MinecraftSource
    with SingleFolderRequirement
    implements FolderBackedScreenshotSource {
  const MinecraftSource({
    this.importer = const MediaImporter(),
    this.sourcePaths = const SourcePathResolver(),
  });

  final MediaImporter importer;
  final SourcePathResolver sourcePaths;

  static const id = 'minecraft';
  static const gameName = 'Minecraft';
  static const platform = 'PC';

  @override
  String get name => gameName;

  @override
  String get folderGrantId => FolderGrantIds.minecraft;

  @override
  bool isEnabled(AppSettings settings) => settings.minecraft.enabled;

  @override
  SourceFolderRequirement? folderRequirement(AppSettings settings) {
    final config = settings.minecraft;
    if (config.useCustomPath) {
      final path = config.sourcePath.trim();
      return path.isEmpty
          ? null
          : SourceFolderRequirement(
              id: folderGrantId,
              path: expandUserPath(path),
              automatic: false,
            );
    }

    final configured = config.sourcePath.trim();
    final paths = configured.isEmpty
        ? sourcePaths.minecraftScreenshots()
        : [expandUserPath(configured)];
    return paths.isEmpty
        ? null
        : SourceFolderRequirement(
            id: folderGrantId,
            path: paths.first,
            automatic: true,
          );
  }

  @override
  AppSettings withFolderPath(AppSettings settings, String path) {
    return settings.copyWith(
      minecraft: settings.minecraft.copyWith(
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
    if (!settings.minecraft.enabled) {
      return ImportResult.empty(name);
    }
    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    final sources = _sourceDirectories(settings.minecraft);
    if (sources.isEmpty) {
      if (!settings.minecraft.useCustomPath) {
        return const ImportResult.warning(
          gameName,
          'Minecraft was skipped because no installation was found.',
        );
      }
      throw const FileSystemException(
        'Choose a Minecraft screenshot folder in Settings.',
      );
    }

    final existingSources = <Directory>[];
    for (final source in sources) {
      if (await source.exists()) {
        existingSources.add(source);
      }
    }
    if (existingSources.isEmpty) {
      if (!settings.minecraft.useCustomPath) {
        return const ImportResult.warning(
          gameName,
          'Minecraft was skipped because no installation was found.',
        );
      }
      throw FileSystemException(
        'The selected Minecraft screenshot folder does not exist.',
        settings.minecraft.sourcePath,
      );
    }

    onProgress?.call(
      const SourceProgress(message: 'Scanning Minecraft screenshots…'),
    );
    final files = <File>[];
    for (final source in existingSources) {
      files.addAll(
        await source
            .list(followLinks: false)
            .where((entity) => entity is File && _isScreenshot(entity.path))
            .cast<File>()
            .toList(),
      );
    }
    files.sort((left, right) => left.path.compareTo(right.path));

    final destination = Directory(
      p.join(expandUserPath(outputPath), platform, gameName),
    );
    var imported = 0;
    var skipped = 0;
    for (var index = 0; index < files.length; index++) {
      onProgress?.call(
        SourceProgress(
          message: 'Importing Minecraft screenshots…',
          completed: index,
          total: files.length,
        ),
      );
      if (await importer.copyByModifiedDate(files[index], destination)) {
        imported++;
      } else {
        skipped++;
      }
    }
    onProgress?.call(
      SourceProgress(
        message: 'Processed Minecraft screenshots.',
        completed: files.length,
        total: files.length,
      ),
    );
    return ImportResult(source: name, imported: imported, skipped: skipped);
  }

  List<Directory> _sourceDirectories(SourceSettings settings) {
    final configured = settings.sourcePath.trim();
    if (settings.useCustomPath) {
      return configured.isEmpty
          ? const []
          : [Directory(expandUserPath(configured))];
    }
    final paths = configured.isEmpty
        ? sourcePaths.minecraftScreenshots()
        : [expandUserPath(configured)];
    return paths.map(Directory.new).toList(growable: false);
  }

  static bool _isScreenshot(String path) {
    return p.extension(path).toLowerCase() == '.png';
  }
}
