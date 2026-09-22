import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/app_log.dart';
import '../services/battle_net_games.dart';
import '../services/folder_access_service.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import 'screenshot_source.dart';

/// One source over several Blizzard games.
///
/// Nothing here reads Battle.net's own configuration. Each game is found by
/// looking for its screenshot folder, which needs no folder grant, and each
/// game carries its own switch, its own grant and its own custom folder.
class BattleNetSource implements FolderBackedScreenshotSource {
  const BattleNetSource({
    this.importer = const MediaImporter(),
    this.locator = const BattleNetLocator(),
  });

  final MediaImporter importer;
  final BattleNetLocator locator;

  static const id = 'battle_net';
  static const sourceName = 'Battle.net';
  static const platform = 'PC';

  /// The grant a game's folder is stored under.
  static String grantIdForGame(String gameId) =>
      '${FolderGrantIds.battleNet}.$gameId';

  @override
  String get name => sourceName;

  @override
  String get folderGrantId => FolderGrantIds.battleNet;

  @override
  bool isEnabled(AppSettings settings) => settings.battleNet.enabled;

  /// Every game with its resolved folder, in table order, whether or not it is
  /// enabled or installed. This is what the settings rows render.
  List<BattleNetGameFolder> gameFolders(AppSettings settings) {
    return [
      for (final game in battleNetGames)
        locator.resolve(game, customPath: _customPathFor(settings, game)),
    ];
  }

  String? _customPathFor(AppSettings settings, BattleNetGame game) {
    final gameSettings = settings.battleNet.game(game.id);
    return gameSettings.useCustomPath ? gameSettings.sourcePath : null;
  }

  /// The games that will actually be imported: enabled, and with a folder.
  List<BattleNetGameFolder> _activeFolders(AppSettings settings) {
    if (!settings.battleNet.enabled) {
      return const [];
    }
    return [
      for (final folder in gameFolders(settings))
        if (settings.battleNet.game(folder.game.id).enabled && folder.isUsable)
          folder,
    ];
  }

  @override
  SourceFolderRequirement? folderRequirement(AppSettings settings) {
    final requirements = folderRequirements(settings);
    return requirements.isEmpty ? null : requirements.first;
  }

  @override
  List<SourceFolderRequirement> folderRequirements(AppSettings settings) {
    return [
      for (final folder in _activeFolders(settings))
        SourceFolderRequirement(
          id: grantIdForGame(folder.game.id),
          path: folder.path!,
          automatic: !folder.isCustom,
          description:
              '${folder.game.name} keeps its screenshots in “${folder.path}”.',
        ),
    ];
  }

  @override
  AppSettings withFolderPath(AppSettings settings, String path) {
    // Each game owns its folder, so there is nothing for the source as a
    // whole to store. Folder choices are written per game by the settings
    // page instead.
    return settings;
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

    final folders = _activeFolders(settings);
    if (folders.isEmpty) {
      return const ImportResult.warning(
        sourceName,
        'Battle.net was skipped because none of its games were found. Turn on a game in Settings, or point it at a custom folder.',
      );
    }

    onProgress?.call(
      const SourceProgress(message: 'Looking for Battle.net screenshots…'),
    );

    final media = <_BattleNetMedia>[];
    for (final folder in folders) {
      media.addAll(await _mediaIn(folder));
    }
    media.sort((left, right) => left.file.path.compareTo(right.file.path));

    var imported = 0;
    var skipped = 0;
    for (var index = 0; index < media.length; index++) {
      final item = media[index];
      onProgress?.call(
        SourceProgress(
          message: 'Importing ${item.folder.game.name} screenshots…',
          completed: index,
          total: media.length,
        ),
      );
      final destination = Directory(
        p.join(
          expandUserPath(outputPath),
          platform,
          item.folder.game.albumName,
        ),
      );
      if (await _copy(item, destination) == true) {
        imported++;
      } else {
        skipped++;
      }
    }

    onProgress?.call(
      SourceProgress(
        message: 'Processed Battle.net screenshots.',
        completed: media.length,
        total: media.length,
      ),
    );
    return ImportResult(source: name, imported: imported, skipped: skipped);
  }

  /// Lists one game's folder, leaving the other games alone if it cannot be
  /// read. A lapsed grant on one game is not a reason to import nothing.
  Future<List<_BattleNetMedia>> _mediaIn(BattleNetGameFolder folder) async {
    try {
      return await Directory(folder.path!)
          .list(followLinks: false)
          .where(
            (entity) => entity is File && folder.game.supports(entity.path),
          )
          .cast<File>()
          .map((file) => _BattleNetMedia(folder: folder, file: file))
          .toList();
    } on FileSystemException catch (exception) {
      diagnosticLog.warning(
        'Battle.net could not read the ${folder.game.name} folder "${folder.path}".',
        category: 'source',
        error: exception,
      );
      return const [];
    }
  }

  Future<bool?> _copy(_BattleNetMedia media, Directory destination) async {
    final game = media.folder.game;
    final file = media.file;

    DateTime? capturedAt;
    if (game.captureDate == BattleNetCaptureDate.fileName) {
      capturedAt = parseWorldOfWarcraftScreenshotDate(p.basename(file.path));
      if (capturedAt == null) {
        diagnosticLog.warning(
          'Battle.net skipped "${file.path}": its ${game.name} filename has no valid capture date.',
          category: 'source',
        );
        return null;
      }
    }

    if (p.extension(file.path).toLowerCase() == '.tga') {
      return _copyTga(file, destination, capturedAt);
    }
    return capturedAt == null
        ? importer.copyByModifiedDate(file, destination)
        : importer.copyAtDate(file, destination, capturedAt);
  }

  /// Screenshots saved as TGA are converted, because nothing downstream — the
  /// gallery, thumbnails, the detail view — can display one.
  Future<bool?> _copyTga(
    File file,
    Directory destination,
    DateTime? capturedAt,
  ) async {
    try {
      final decoded = image.decodeTga(await file.readAsBytes());
      if (decoded == null) {
        throw const FormatException('The TGA image could not be decoded.');
      }
      final date = capturedAt ?? (await file.stat()).modified;
      return await importer.writeBytes(
        image.encodePng(decoded),
        destination,
        baseName: formatDate(date),
        extension: '.png',
      );
    } on Object catch (exception) {
      diagnosticLog.warning(
        'Battle.net skipped "${file.path}": its TGA image could not be converted.',
        category: 'source',
        error: exception,
      );
      return null;
    }
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

class _BattleNetMedia {
  const _BattleNetMedia({required this.folder, required this.file});

  final BattleNetGameFolder folder;
  final File file;
}
