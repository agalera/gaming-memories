import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/folder_access_service.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import '../services/provider_paths.dart';
import 'screenshot_provider.dart';

typedef HytaleCoverLoader = Future<List<int>> Function();

class HytaleProvider implements FolderBackedScreenshotProvider {
  HytaleProvider({
    this.importer = const MediaImporter(),
    this.providerPaths = const ProviderPathResolver(),
    HytaleCoverLoader? coverLoader,
  }) : _coverLoader = coverLoader ?? _loadBundledCover;

  final MediaImporter importer;
  final ProviderPathResolver providerPaths;
  final HytaleCoverLoader _coverLoader;

  static const id = 'hytale';
  static const gameName = 'Hytale';
  static const platform = 'PC';
  static const _extensions = {'.png', '.jpg', '.jpeg'};
  static const _coverAsset = 'assets/covers/hytale.png';

  @override
  String get name => gameName;

  @override
  String get folderGrantId => FolderGrantIds.hytale;

  @override
  bool isEnabled(AppSettings settings) => settings.hytale.enabled;

  @override
  ProviderFolderRequirement? folderRequirement(AppSettings settings) {
    final provider = settings.hytale;
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

    final configured = provider.sourcePath.trim();
    final path = configured.isEmpty
        ? providerPaths.hytaleScreenshots()
        : expandUserPath(configured);
    return path == null
        ? null
        : ProviderFolderRequirement(
            id: folderGrantId,
            path: path,
            automatic: true,
          );
  }

  @override
  AppSettings withFolderPath(AppSettings settings, String path) {
    return settings.copyWith(
      hytale: settings.hytale.copyWith(useCustomPath: true, sourcePath: path),
    );
  }

  @override
  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  }) async {
    if (!settings.hytale.enabled) {
      return ImportResult.empty(name);
    }

    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    final destination = Directory(
      p.join(expandUserPath(outputPath), platform, gameName),
    );
    final source = _sourceDirectory(settings.hytale);
    if (source == null) {
      await _writeCoverIfEnabled(settings.hytale, destination);
      if (!settings.hytale.useCustomPath) {
        return const ImportResult.warning(
          gameName,
          'Hytale was skipped because no installation was found.',
        );
      }
      throw const FileSystemException(
        'Choose a Hytale screenshot folder in Settings.',
      );
    }
    if (!await source.exists()) {
      await _writeCoverIfEnabled(settings.hytale, destination);
      if (!settings.hytale.useCustomPath) {
        return const ImportResult.warning(
          gameName,
          'Hytale was skipped because no installation was found.',
        );
      }
      throw FileSystemException(
        'The selected Hytale screenshot folder does not exist.',
        source.path,
      );
    }

    onProgress?.call(
      const ProviderProgress(message: 'Scanning Hytale screenshots…'),
    );
    final files = await source
        .list(followLinks: false)
        .where((entity) => entity is File && _isScreenshot(entity.path))
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));

    var imported = 0;
    var skipped = 0;
    for (var index = 0; index < files.length; index++) {
      onProgress?.call(
        ProviderProgress(
          message: 'Importing Hytale screenshots…',
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

    await _writeCoverIfEnabled(settings.hytale, destination);
    onProgress?.call(
      ProviderProgress(
        message: 'Processed Hytale screenshots.',
        completed: files.length,
        total: files.length,
      ),
    );
    return ImportResult(provider: name, imported: imported, skipped: skipped);
  }

  Directory? _sourceDirectory(ProviderSettings settings) {
    final configured = settings.sourcePath.trim();
    if (settings.useCustomPath) {
      return configured.isEmpty ? null : Directory(expandUserPath(configured));
    }
    final automatic = configured.isEmpty
        ? providerPaths.hytaleScreenshots()
        : expandUserPath(configured);
    return automatic == null ? null : Directory(automatic);
  }

  Future<void> _writeCoverIfEnabled(
    ProviderSettings settings,
    Directory destination,
  ) async {
    if (!settings.downloadCovers) {
      return;
    }
    final bytes = await _coverLoader();
    await destination.create(recursive: true);
    final cover = File(p.join(destination.path, 'cover.png'));
    if (!await cover.exists() ||
        !listEquals(await cover.readAsBytes(), bytes)) {
      await cover.writeAsBytes(bytes, flush: true);
    }
  }

  static bool _isScreenshot(String path) {
    return _extensions.contains(p.extension(path).toLowerCase());
  }

  static Future<List<int>> _loadBundledCover() async {
    final data = await rootBundle.load(_coverAsset);
    return Uint8List.sublistView(data);
  }
}
