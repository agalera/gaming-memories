import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/exiftool_service.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import 'screenshot_provider.dart';

class GuildWars2Provider implements ScreenshotProvider {
  const GuildWars2Provider({
    this.importer = const MediaImporter(),
    this.dateReader = const ExifToolDateReader(),
  });

  final MediaImporter importer;
  final ExifDateReader dateReader;

  static const id = 'guild_wars_2';
  static const gameName = 'Guild Wars 2';
  static const platform = 'PC';

  @override
  String get name => gameName;

  @override
  bool isEnabled(AppSettings settings) => settings.guildWars2.enabled;

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

    await dateReader.ensureAvailable();
    onProgress?.call(
      const ProviderProgress(message: 'Scanning Guild Wars 2 screenshots…'),
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
        ProviderProgress(
          message: 'Importing Guild Wars 2 screenshots…',
          completed: index,
          total: files.length,
        ),
      );
      final capturedAt = await dateReader.fileModifiedAt(files[index]);
      final copied = await importer.copyAtDate(
        files[index],
        destination,
        capturedAt,
      );
      if (copied) {
        imported++;
      } else {
        skipped++;
      }
    }

    onProgress?.call(
      ProviderProgress(
        message: 'Processed Guild Wars 2 screenshots.',
        completed: files.length,
        total: files.length,
      ),
    );
    return ImportResult(provider: name, imported: imported, skipped: skipped);
  }

  Directory? _sourceDirectory(ProviderSettings settings) {
    final path = settings.sourcePath.trim();
    if (settings.useCustomPath) {
      if (path.isEmpty) {
        return null;
      }
      return Directory(expandUserPath(path));
    }

    if (!Platform.isWindows) {
      return null;
    }

    final home = homeDirectory();
    return home == null
        ? null
        : Directory(p.join(home, 'Documents', 'Guild Wars 2', 'Screens'));
  }

  bool _isScreenshot(String path) {
    return p.extension(path).toLowerCase() == '.jpg';
  }
}
