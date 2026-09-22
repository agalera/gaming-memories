import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import '../services/folder_access_service.dart';
import '../services/source_paths.dart';
import 'screenshot_source.dart';

class GuildWars2Source
    with SingleFolderRequirement
    implements FolderBackedScreenshotSource {
  const GuildWars2Source({this.importer = const MediaImporter()});

  final MediaImporter importer;

  static const id = 'guild_wars_2';
  static const gameName = 'Guild Wars 2';
  static const platform = 'PC';

  @override
  String get name => gameName;

  @override
  String get folderGrantId => FolderGrantIds.guildWars2;

  @override
  bool isEnabled(AppSettings settings) => settings.guildWars2.enabled;

  @override
  SourceFolderRequirement? folderRequirement(AppSettings settings) {
    final config = settings.guildWars2;
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
    final path = SourcePaths.guildWars2Screenshots();
    return path == null
        ? null
        : SourceFolderRequirement(
            id: folderGrantId,
            path: path,
            automatic: true,
          );
  }

  @override
  AppSettings withFolderPath(AppSettings settings, String path) {
    return settings.copyWith(
      guildWars2: settings.guildWars2.copyWith(
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
    if (!settings.guildWars2.enabled) {
      return ImportResult.empty(name);
    }

    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    final source = _sourceDirectory(settings.guildWars2);
    if (source == null) {
      if (!settings.guildWars2.useCustomPath) {
        return const ImportResult.warning(
          gameName,
          'Guild Wars 2 was skipped because no installation was found.',
        );
      }
      throw const FileSystemException(
        'Choose a Guild Wars 2 screenshot folder in Settings.',
      );
    }
    if (!await source.exists()) {
      if (!settings.guildWars2.useCustomPath) {
        return const ImportResult.warning(
          gameName,
          'Guild Wars 2 was skipped because no installation was found.',
        );
      }
      throw FileSystemException(
        'The selected Guild Wars 2 screenshot folder does not exist.',
        source.path,
      );
    }

    onProgress?.call(
      const SourceProgress(message: 'Scanning Guild Wars 2 screenshots…'),
    );
    final files = await source
        .list(followLinks: false)
        .where((entity) => entity is File && _isScreenshot(entity.path))
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));

    final destination = Directory(
      p.join(expandUserPath(outputPath), platform, gameName),
    );
    var imported = 0;
    var skipped = 0;
    for (var index = 0; index < files.length; index++) {
      onProgress?.call(
        SourceProgress(
          message: 'Importing Guild Wars 2 screenshots…',
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
      SourceProgress(
        message: 'Processed Guild Wars 2 screenshots.',
        completed: files.length,
        total: files.length,
      ),
    );
    return ImportResult(source: name, imported: imported, skipped: skipped);
  }

  Directory? _sourceDirectory(SourceSettings settings) {
    final path = settings.sourcePath.trim();
    if (settings.useCustomPath) {
      if (path.isEmpty) {
        return null;
      }
      return Directory(expandUserPath(path));
    }

    final automatic = SourcePaths.guildWars2Screenshots();
    return automatic == null ? null : Directory(automatic);
  }

  bool _isScreenshot(String path) {
    return p.extension(path).toLowerCase() == '.jpg';
  }
}
