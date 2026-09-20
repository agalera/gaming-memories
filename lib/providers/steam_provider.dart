import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import '../services/folder_access_service.dart';
import '../services/provider_paths.dart';
import '../services/steam_client.dart';
import 'screenshot_provider.dart';

class SteamProvider implements FolderBackedScreenshotProvider {
  const SteamProvider({
    required this.api,
    this.importer = const MediaImporter(),
    this.providerPaths = const ProviderPathResolver(),
  });

  final SteamApi api;
  final MediaImporter importer;
  final ProviderPathResolver providerPaths;

  @override
  String get name => 'Steam';

  @override
  String get folderGrantId => FolderGrantIds.steam;

  @override
  bool isEnabled(AppSettings settings) => settings.steam.enabled;

  @override
  ProviderFolderRequirement? folderRequirement(AppSettings settings) {
    final steam = settings.steam;
    if (steam.useCustomPath) {
      final path = steam.userdataPath.trim();
      return path.isEmpty
          ? null
          : ProviderFolderRequirement(
              id: folderGrantId,
              path: expandUserPath(path),
              automatic: false,
            );
    }
    final configured = steam.userdataPath.trim();
    final path = configured.isEmpty
        ? providerPaths.steamUserdata()
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
      steam: settings.steam.copyWith(useCustomPath: true, userdataPath: path),
    );
  }

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

    games.addAll(
      await _migrateCustomAlbums(
        settings,
        ignored: ignored,
        onProgress: onProgress,
      ),
    );

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
    final userdata = _userdataDirectory(settings);
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

  Future<Map<String, String>> _migrateCustomAlbums(
    AppSettings settings, {
    required Set<String> ignored,
    ProgressCallback? onProgress,
  }) async {
    final entries = settings.steam.customGames.entries
        .where(
          (entry) =>
              entry.key.trim().isNotEmpty &&
              entry.value.trim().isNotEmpty &&
              !ignored.contains(entry.key.trim()),
        )
        .toList(growable: false);
    final migrated = <String, String>{};

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      onProgress?.call(
        ProviderProgress(
          message: 'Applying custom Steam game names…',
          completed: index,
          total: entries.length,
        ),
      );

      String? original;
      try {
        original = await api.gameName(
          entry.key.trim(),
          settings.steam.apiKey.trim(),
        );
      } on Exception {
        continue;
      }
      if (original == null || original.trim().isEmpty) {
        continue;
      }

      final originalName = _safeName(original);
      final customName = _safeName(entry.value);
      if (originalName == customName) {
        continue;
      }

      final source = _destination(settings.outputPath, originalName);
      if (!await source.exists()) {
        continue;
      }
      await _mergeAlbum(source, _destination(settings.outputPath, customName));
      migrated[entry.key.trim()] = customName;
    }

    if (entries.isNotEmpty) {
      onProgress?.call(
        ProviderProgress(
          message: 'Applied custom Steam game names.',
          completed: entries.length,
          total: entries.length,
        ),
      );
    }
    return migrated;
  }

  Future<void> _mergeAlbum(Directory source, Directory destination) async {
    if (_samePath(source.path, destination.path)) {
      return;
    }
    if (!await destination.exists()) {
      await destination.parent.create(recursive: true);
      try {
        await source.rename(destination.path);
        return;
      } on FileSystemException {
        // A file-by-file move supports file systems that cannot rename here.
      }
    }

    await destination.create(recursive: true);
    final files = await source
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));

    for (final file in files) {
      final relative = p.relative(file.path, from: source.path);
      final target = File(p.join(destination.path, relative));
      await target.parent.create(recursive: true);
      await _mergeFile(file, target);
    }
    if (await source.exists()) {
      await source.delete(recursive: true);
    }
  }

  Future<void> _mergeFile(File source, File target) async {
    if (!await target.exists()) {
      await _moveFile(source, target);
      return;
    }

    final sourceBytes = await source.readAsBytes();
    if (sha1.convert(sourceBytes) == sha1.convert(await target.readAsBytes())) {
      await source.delete();
      return;
    }

    if (p.basename(target.path).toLowerCase() == 'cover.jpg') {
      await source.delete();
      return;
    }

    final digest = sha1.convert(sourceBytes);
    final collision = File(
      p.join(
        target.parent.path,
        '${p.basenameWithoutExtension(target.path)}_$digest'
        '${p.extension(target.path)}',
      ),
    );
    if (await collision.exists()) {
      if (sha1.convert(await collision.readAsBytes()) != digest) {
        throw FileSystemException(
          'A renamed Steam file has a content hash collision.',
          collision.path,
        );
      }
      await source.delete();
      return;
    }
    await _moveFile(source, collision);
  }

  Future<void> _moveFile(File source, File target) async {
    try {
      await source.rename(target.path);
    } on FileSystemException {
      final modified = (await source.stat()).modified;
      await source.copy(target.path);
      await target.setLastModified(modified);
      await source.delete();
    }
  }

  bool _samePath(String left, String right) {
    final normalizedLeft = p.normalize(p.absolute(left));
    final normalizedRight = p.normalize(p.absolute(right));
    return Platform.isWindows
        ? normalizedLeft.toLowerCase() == normalizedRight.toLowerCase()
        : normalizedLeft == normalizedRight;
  }

  Directory? _userdataDirectory(SteamSettings settings) {
    final configured = settings.userdataPath.trim();
    if (settings.useCustomPath) {
      if (configured.isEmpty) {
        return null;
      }
      final directory = Directory(expandUserPath(configured));
      return p.basename(directory.path).toLowerCase() == 'userdata'
          ? directory
          : Directory(p.join(directory.path, 'userdata'));
    }

    final automatic = configured.isEmpty
        ? providerPaths.steamUserdata()
        : expandUserPath(configured);
    return automatic == null ? null : Directory(automatic);
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
