import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import '../services/steam_client.dart';
import 'screenshot_provider.dart';

class SteamProvider implements ScreenshotProvider {
  const SteamProvider({
    required this.api,
    this.importer = const MediaImporter(),
  });

  final SteamApi api;
  final MediaImporter importer;

  @override
  String get name => 'Steam';

  @override
  bool isEnabled(AppSettings settings) => settings.steam.enabled;

  @override
  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  }) async {
    if (!settings.steam.enabled) {
      return ImportResult.empty(name);
    }
    if (settings.outputPath.trim().isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    final ignored = settings.steam.ignoredGames
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    var imported = 0;
    var skipped = 0;
    final games = <String, String>{};

    onProgress?.call(
      const ProviderProgress(message: 'Scanning local Steam screenshots…'),
    );
    final local = await _localScreenshots(settings.steam);
    final localTotal = local.entries
        .where((entry) => !ignored.contains(entry.key))
        .fold(0, (total, entry) => total + entry.value.length);
    var localCompleted = 0;
    for (final entry in local.entries) {
      final appId = entry.key;
      if (ignored.contains(appId)) {
        continue;
      }
      final gameName = await _gameName(appId, settings.steam);
      games[appId] = gameName;
      final destination = _destination(settings.outputPath, gameName);
      for (final source in entry.value) {
        onProgress?.call(
          ProviderProgress(
            message: 'Importing local Steam screenshots…',
            completed: localCompleted,
            total: localTotal,
          ),
        );
        if (await importer.copyByModifiedDate(source, destination)) {
          imported++;
        } else {
          skipped++;
        }
        localCompleted++;
      }
    }
    if (localTotal > 0) {
      onProgress?.call(
        ProviderProgress(
          message: 'Processed local Steam screenshots.',
          completed: localTotal,
          total: localTotal,
        ),
      );
    }

    if (settings.steam.onlineGallery) {
      onProgress?.call(
        const ProviderProgress(message: 'Reading the Steam online gallery…'),
      );
      final screenshots = await api.publishedScreenshots(
        settings.steam.userId.trim(),
        settings.steam.apiKey.trim(),
      );
      for (var index = 0; index < screenshots.length; index++) {
        final screenshot = screenshots[index];
        onProgress?.call(
          ProviderProgress(
            message: 'Importing online Steam screenshots…',
            completed: index,
            total: screenshots.length,
          ),
        );
        var appId = screenshot.appId;
        if (appId == '0') {
          appId =
              await api.appIdForName(
                screenshot.shortcutName,
                settings.steam.apiKey.trim(),
              ) ??
              '';
        }
        if (appId.isEmpty || ignored.contains(appId)) {
          continue;
        }
        final gameName = await _gameName(appId, settings.steam);
        games[appId] = gameName;
        if (screenshot.fileUrl.isEmpty) {
          continue;
        }
        final bytes = await api.download(screenshot.fileUrl);
        final added = await importer.writeBytes(
          bytes,
          _destination(settings.outputPath, gameName),
          baseName: formatDate(screenshot.createdAt),
          extension: '.jpg',
        );
        if (added) {
          imported++;
        } else {
          skipped++;
        }
      }
      if (screenshots.isNotEmpty) {
        onProgress?.call(
          ProviderProgress(
            message: 'Processed online Steam screenshots.',
            completed: screenshots.length,
            total: screenshots.length,
          ),
        );
      }
    }

    if (settings.steam.downloadCovers) {
      final entries = games.entries.toList(growable: false);
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        onProgress?.call(
          ProviderProgress(
            message: 'Downloading Steam game covers…',
            completed: index,
            total: entries.length,
          ),
        );
        List<int>? cover;
        try {
          cover = await api.gameCover(entry.key);
        } on Exception {
          continue;
        }
        if (cover == null) {
          continue;
        }
        await _writeCover(
          cover,
          _destination(settings.outputPath, entry.value),
        );
      }
      if (entries.isNotEmpty) {
        onProgress?.call(
          ProviderProgress(
            message: 'Processed Steam game covers.',
            completed: entries.length,
            total: entries.length,
          ),
        );
      }
    }

    onProgress?.call(
      const ProviderProgress(message: 'Steam collection is complete.'),
    );

    return ImportResult(provider: name, imported: imported, skipped: skipped);
  }

  Future<Map<String, List<File>>> _localScreenshots(
    SteamSettings settings,
  ) async {
    final userdata = _userdataDirectory(settings.userdataPath);
    if (userdata == null || !await userdata.exists()) {
      return const {};
    }

    final screenshots = <String, List<File>>{};
    await for (final user in userdata.list(followLinks: false)) {
      if (user is! Directory) {
        continue;
      }
      final remote = Directory(p.join(user.path, '760', 'remote'));
      if (!await remote.exists()) {
        continue;
      }
      await for (final app in remote.list(followLinks: false)) {
        if (app is! Directory) {
          continue;
        }
        final directory = Directory(p.join(app.path, 'screenshots'));
        if (!await directory.exists()) {
          continue;
        }
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is File &&
              {
                '.jpg',
                '.jpeg',
              }.contains(p.extension(entity.path).toLowerCase())) {
            screenshots.putIfAbsent(p.basename(app.path), () => []).add(entity);
          }
        }
      }
    }
    for (final files in screenshots.values) {
      files.sort((left, right) => left.path.compareTo(right.path));
    }
    return screenshots;
  }

  Directory? _userdataDirectory(String configuredPath) {
    final configured = configuredPath.trim();
    if (configured.isNotEmpty && configured != 'auto') {
      final directory = Directory(expandUserPath(configured));
      return p.basename(directory.path).toLowerCase() == 'userdata'
          ? directory
          : Directory(p.join(directory.path, 'userdata'));
    }

    final home = homeDirectory();
    if (Platform.isWindows) {
      return Directory(r'C:\Program Files (x86)\Steam\userdata');
    }
    if (home == null) {
      return null;
    }
    if (Platform.isMacOS) {
      return Directory(
        p.join(home, 'Library', 'Application Support', 'Steam', 'userdata'),
      );
    }
    if (Platform.isLinux) {
      return Directory(p.join(home, '.local', 'share', 'Steam', 'userdata'));
    }
    return null;
  }

  Future<String> _gameName(String appId, SteamSettings settings) async {
    final custom = settings.customGames[appId]?.trim();
    if (custom != null && custom.isNotEmpty) {
      return _safeName(custom);
    }
    final resolved = await api.gameName(appId, settings.apiKey.trim());
    return _safeName(resolved?.trim().isNotEmpty == true ? resolved! : appId);
  }

  Directory _destination(String outputPath, String gameName) {
    return Directory(p.join(expandUserPath(outputPath.trim()), 'PC', gameName));
  }

  Future<void> _writeCover(List<int> bytes, Directory destination) async {
    await destination.create(recursive: true);
    final cover = File(p.join(destination.path, 'cover.jpg'));
    if (!await cover.exists() ||
        (await cover.readAsBytes()).toString() != bytes.toString()) {
      await cover.writeAsBytes(bytes, flush: true);
    }
  }

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'Unknown Steam game' : cleaned;
  }
}
