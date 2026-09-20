import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/battle_net_catalog.dart';
import '../services/folder_access_service.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import '../services/provider_paths.dart';
import 'screenshot_provider.dart';

class BattleNetProvider implements FolderBackedScreenshotProvider {
  const BattleNetProvider({
    this.importer = const MediaImporter(),
    this.providerPaths = const ProviderPathResolver(),
    this.catalog = const ProductDatabaseBattleNetCatalog(),
  });

  final MediaImporter importer;
  final ProviderPathResolver providerPaths;
  final BattleNetCatalog catalog;

  static const id = 'battle_net';
  static const providerName = 'Battle.net';
  static const platform = 'PC';
  static const diabloIVGameName = 'Diablo IV';
  static const worldOfWarcraftGameName = 'World of Warcraft';
  static const _wowUids = {'wow', 'wow_classic', 'wow_classic_era'};
  static const _wowFlavors = {
    'wow': '_retail_',
    'wow_classic': '_classic_',
    'wow_classic_era': '_classic_era_',
  };

  @override
  String get name => providerName;

  @override
  String get folderGrantId => FolderGrantIds.battleNet;

  @override
  bool isEnabled(AppSettings settings) => settings.battleNet.enabled;

  @override
  ProviderFolderRequirement? folderRequirement(AppSettings settings) {
    final provider = settings.battleNet;
    final configured = provider.sourcePath.trim();
    if (configured.isNotEmpty) {
      return ProviderFolderRequirement(
        id: folderGrantId,
        path: expandUserPath(configured),
        automatic: !provider.useCustomPath,
      );
    }
    if (provider.useCustomPath) {
      return null;
    }
    final candidates = providerPaths.battleNetRootCandidates();
    return candidates.isEmpty
        ? null
        : ProviderFolderRequirement(
            id: folderGrantId,
            path: candidates.first,
            automatic: true,
          );
  }

  @override
  AppSettings withFolderPath(AppSettings settings, String path) {
    return settings.copyWith(
      battleNet: settings.battleNet.copyWith(
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
    if (!settings.battleNet.enabled) {
      return ImportResult.empty(name);
    }
    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    final configuredPath = settings.battleNet.sourcePath.trim();
    if (settings.battleNet.useCustomPath && configuredPath.isEmpty) {
      throw const FileSystemException(
        'Choose a Battle.net or game installation folder in Settings.',
      );
    }
    if (configuredPath.isNotEmpty &&
        !await Directory(expandUserPath(configuredPath)).exists()) {
      if (settings.battleNet.useCustomPath) {
        throw FileSystemException(
          'The selected Battle.net folder does not exist.',
          configuredPath,
        );
      }
      return const ImportResult.warning(
        providerName,
        'Battle.net was skipped because no supported installation was found.',
      );
    }

    onProgress?.call(
      const ProviderProgress(message: 'Discovering Battle.net games…'),
    );
    final sources = configuredPath.isNotEmpty
        ? await _sourcesFromRoot(Directory(expandUserPath(configuredPath)))
        : await _automaticSources();
    if (sources.isEmpty) {
      if (settings.battleNet.useCustomPath) {
        throw FileSystemException(
          'The selected folder contains no Diablo IV or World of Warcraft screenshots.',
          configuredPath,
        );
      }
      return const ImportResult.warning(
        providerName,
        'Battle.net was skipped because no Diablo IV or World of Warcraft screenshot folders were found.',
      );
    }

    final files = <_BattleNetMedia>[];
    for (final source in sources) {
      final sourceFiles = await source.directory
          .list(followLinks: false)
          .where(
            (entity) => entity is File && source.kind.supports(entity.path),
          )
          .cast<File>()
          .map((file) => _BattleNetMedia(source: source, file: file))
          .toList();
      files.addAll(sourceFiles);
    }
    files.sort((left, right) => left.file.path.compareTo(right.file.path));

    var imported = 0;
    var skipped = 0;
    for (var index = 0; index < files.length; index++) {
      final media = files[index];
      onProgress?.call(
        ProviderProgress(
          message: 'Importing ${media.source.gameName} screenshots…',
          completed: index,
          total: files.length,
        ),
      );
      final destination = Directory(
        p.join(expandUserPath(outputPath), platform, media.source.gameName),
      );
      final copied = switch (media.source.kind) {
        _BattleNetGame.diabloIV => await importer.copyByModifiedDate(
          media.file,
          destination,
        ),
        _BattleNetGame.worldOfWarcraft => await _copyWorldOfWarcraft(
          media.file,
          destination,
        ),
      };
      if (copied == null) {
        skipped++;
      } else if (copied) {
        imported++;
      } else {
        skipped++;
      }
    }

    onProgress?.call(
      ProviderProgress(
        message: 'Processed Battle.net screenshots.',
        completed: files.length,
        total: files.length,
      ),
    );
    return ImportResult(provider: name, imported: imported, skipped: skipped);
  }

  Future<bool?> _copyWorldOfWarcraft(File file, Directory destination) async {
    final capturedAt = parseWorldOfWarcraftScreenshotDate(
      p.basename(file.path),
    );
    if (capturedAt == null) {
      debugPrint(
        '[Gaming Memories] Battle.net skipped "${file.path}" because its World of Warcraft filename has no valid capture date.',
      );
      return null;
    }
    if (p.extension(file.path).toLowerCase() != '.tga') {
      return importer.copyAtDate(file, destination, capturedAt);
    }

    try {
      final decoded = image.decodeTga(await file.readAsBytes());
      if (decoded == null) {
        throw const FormatException('The TGA image could not be decoded.');
      }
      return await importer.writeBytes(
        image.encodePng(decoded),
        destination,
        baseName: formatDate(capturedAt),
        extension: '.png',
      );
    } on Object catch (exception) {
      debugPrint(
        '[Gaming Memories] Battle.net skipped "${file.path}" because its TGA image could not be converted: $exception',
      );
      return null;
    }
  }

  Future<List<_BattleNetSource>> _automaticSources() async {
    final installs = await catalog.installations();
    return _sourcesFromInstalls(installs);
  }

  Future<List<_BattleNetSource>> _sourcesFromRoot(Directory root) async {
    final sources = <_BattleNetSource>[];
    await _addRecognizedRoot(sources, root);
    final installs = await catalog.installations(rootPath: root.path);
    sources.addAll(await _sourcesFromInstalls(installs, customRoot: root.path));
    return _existingUniqueSources(sources);
  }

  Future<List<_BattleNetSource>> _sourcesFromInstalls(
    List<BattleNetInstall> installs, {
    String? customRoot,
  }) async {
    final sources = <_BattleNetSource>[];
    for (final install in installs) {
      if (_wowUids.contains(install.uid) && install.installPath.isNotEmpty) {
        final root = Directory(
          _translateInstallPath(install.installPath, customRoot),
        );
        await _addWorldOfWarcraftRoot(
          sources,
          root,
          preferredFlavor: _wowFlavors[install.uid],
        );
      }
      if (install.uid == 'fenris') {
        if (customRoot == null) {
          sources.addAll(
            providerPaths.diabloIVScreenshots().map(
              (path) => _BattleNetSource(
                gameName: diabloIVGameName,
                directory: Directory(path),
                kind: _BattleNetGame.diabloIV,
              ),
            ),
          );
        } else {
          await _addWineDiabloSources(sources, Directory(customRoot));
        }
      }
    }
    return _existingUniqueSources(sources);
  }

  Future<void> _addRecognizedRoot(
    List<_BattleNetSource> sources,
    Directory root,
  ) async {
    final normalized = root.path.toLowerCase();
    final base = p.basename(root.path).toLowerCase();
    final parent = p.basename(root.parent.path).toLowerCase();

    if (base == 'screenshots' &&
        (parent.startsWith('_') || normalized.contains('world of warcraft'))) {
      sources.add(
        _BattleNetSource(
          gameName: worldOfWarcraftGameName,
          directory: root,
          kind: _BattleNetGame.worldOfWarcraft,
        ),
      );
    } else {
      await _addWorldOfWarcraftRoot(sources, root);
      await _addWorldOfWarcraftRoot(
        sources,
        Directory(p.join(root.path, 'World of Warcraft')),
      );
    }

    if (normalized.contains('diablo iv') &&
        (base == 'screenshots' || base == 'diablo iv')) {
      final direct = base == 'screenshots'
          ? root
          : Directory(p.join(root.path, 'Screenshots'));
      sources.add(
        _BattleNetSource(
          gameName: diabloIVGameName,
          directory: await direct.exists() ? direct : root,
          kind: _BattleNetGame.diabloIV,
        ),
      );
    }
    for (final candidate in [
      p.join(root.path, 'Documents', 'Diablo IV', 'Screenshots'),
      p.join(root.path, 'Pictures', 'Diablo IV'),
    ]) {
      sources.add(
        _BattleNetSource(
          gameName: diabloIVGameName,
          directory: Directory(candidate),
          kind: _BattleNetGame.diabloIV,
        ),
      );
    }
    await _addWineDiabloSources(sources, root);
  }

  Future<void> _addWorldOfWarcraftRoot(
    List<_BattleNetSource> sources,
    Directory root, {
    String? preferredFlavor,
  }) async {
    final base = p.basename(root.path);
    if (base.startsWith('_')) {
      sources.add(
        _BattleNetSource(
          gameName: worldOfWarcraftGameName,
          directory: Directory(p.join(root.path, 'Screenshots')),
          kind: _BattleNetGame.worldOfWarcraft,
        ),
      );
      return;
    }
    final flavors = preferredFlavor == null
        ? _wowFlavors.values
        : [preferredFlavor];
    for (final flavor in flavors) {
      sources.add(
        _BattleNetSource(
          gameName: worldOfWarcraftGameName,
          directory: Directory(p.join(root.path, flavor, 'Screenshots')),
          kind: _BattleNetGame.worldOfWarcraft,
        ),
      );
    }
  }

  Future<void> _addWineDiabloSources(
    List<_BattleNetSource> sources,
    Directory root,
  ) async {
    final users = Directory(p.join(root.path, 'drive_c', 'users'));
    if (!await users.exists()) {
      return;
    }
    await for (final entity in users.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      sources.addAll([
        _BattleNetSource(
          gameName: diabloIVGameName,
          directory: Directory(
            p.join(entity.path, 'Documents', 'Diablo IV', 'Screenshots'),
          ),
          kind: _BattleNetGame.diabloIV,
        ),
        _BattleNetSource(
          gameName: diabloIVGameName,
          directory: Directory(p.join(entity.path, 'Pictures', 'Diablo IV')),
          kind: _BattleNetGame.diabloIV,
        ),
      ]);
    }
  }

  Future<List<_BattleNetSource>> _existingUniqueSources(
    List<_BattleNetSource> sources,
  ) async {
    final unique = <String, _BattleNetSource>{};
    for (final source in sources) {
      if (await source.directory.exists()) {
        unique[p.normalize(source.directory.path)] = source;
      }
    }
    return unique.values.toList(growable: false);
  }

  String _translateInstallPath(String path, String? customRoot) {
    if (customRoot == null || !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      return path;
    }
    final relative = path
        .substring(3)
        .split(RegExp(r'[\\/]'))
        .where((part) => part.isNotEmpty);
    return p.joinAll([customRoot, 'drive_c', ...relative]);
  }
}

DateTime? parseWorldOfWarcraftScreenshotDate(String name) {
  final match = RegExp(
    r'^WoWScrnShot_(\d{2})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.(?:jpe?g|png|tga)$',
    caseSensitive: false,
  ).firstMatch(name);
  if (match == null) {
    return null;
  }
  final values = [
    for (var index = 1; index <= 6; index++) int.parse(match.group(index)!),
  ];
  final year = values[2] >= 69 ? 1900 + values[2] : 2000 + values[2];
  final capturedAt = DateTime(
    year,
    values[0],
    values[1],
    values[3],
    values[4],
    values[5],
  );
  if (capturedAt.year != year ||
      capturedAt.month != values[0] ||
      capturedAt.day != values[1] ||
      capturedAt.hour != values[3] ||
      capturedAt.minute != values[4] ||
      capturedAt.second != values[5]) {
    return null;
  }
  return capturedAt;
}

enum _BattleNetGame {
  diabloIV({'.jpg', '.jpeg', '.png'}),
  worldOfWarcraft({'.jpg', '.jpeg', '.png', '.tga'});

  const _BattleNetGame(this.extensions);

  final Set<String> extensions;

  bool supports(String path) =>
      !p.basename(path).startsWith('.') &&
      extensions.contains(p.extension(path).toLowerCase());
}

class _BattleNetSource {
  const _BattleNetSource({
    required this.gameName,
    required this.directory,
    required this.kind,
  });

  final String gameName;
  final Directory directory;
  final _BattleNetGame kind;
}

class _BattleNetMedia {
  const _BattleNetMedia({required this.source, required this.file});

  final _BattleNetSource source;
  final File file;
}
