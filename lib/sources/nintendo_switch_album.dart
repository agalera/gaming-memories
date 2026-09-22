import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/app_log.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import '../services/mtp_client.dart';
import 'screenshot_source.dart';

/// The USB vendor ID every Nintendo console reports.
const nintendoVendorId = '057e';

/// Both console generations share their album the same way: Album, then
/// Copy to a Computer, over USB as an MTP device. They differ in the product
/// ID they report, in the album they write to, and in nothing else, so the
/// collection itself lives here.
abstract class NintendoSwitchAlbumSource
    with SingleFolderRequirement
    implements FolderBackedScreenshotSource {
  const NintendoSwitchAlbumSource({
    required this.importer,
    required this.mtpClient,
    required this.usbDeviceFinder,
    required this.operatingSystem,
  });

  final MediaImporter importer;
  final MtpClient mtpClient;
  final UsbDeviceFinder usbDeviceFinder;
  final String? operatingSystem;

  String get id;

  /// What the console reports while it shares its album. In any other mode it
  /// answers on a different interface, so the product ID is what says the
  /// album is there.
  String get albumProductId;

  NintendoSwitchSettings config(AppSettings settings);

  @override
  bool isEnabled(AppSettings settings) => config(settings).enabled;

  @override
  SourceFolderRequirement? folderRequirement(AppSettings settings) {
    final source = config(settings);
    if (!source.useCustomPath || source.sourcePath.trim().isEmpty) {
      return null;
    }
    return SourceFolderRequirement(
      id: folderGrantId,
      path: expandUserPath(source.sourcePath.trim()),
      automatic: false,
    );
  }

  @override
  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  }) async {
    final source = config(settings);
    if (!source.enabled) {
      return ImportResult.empty(name);
    }
    if (settings.outputPath.trim().isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    if (source.useCustomPath) {
      final sourcePath = source.sourcePath.trim();
      if (sourcePath.isEmpty) {
        throw FileSystemException(
          'Choose a copied $name album folder in Settings.',
        );
      }
      return _collectFromFolder(
        Directory(expandUserPath(sourcePath)),
        settings,
        onProgress,
      );
    }

    if ((operatingSystem ?? Platform.operatingSystem) != 'linux') {
      return ImportResult.warning(
        name,
        '$name direct USB collection is available on Linux. Select a copied album folder in Settings on this computer.',
      );
    }
    return _collectFromConsole(settings, onProgress);
  }

  Future<ImportResult> _collectFromFolder(
    Directory source,
    AppSettings settings,
    ProgressCallback? onProgress,
  ) async {
    if (!await source.exists()) {
      throw FileSystemException(
        'The selected $name album folder does not exist.',
        source.path,
      );
    }

    onProgress?.call(SourceProgress(message: 'Scanning $name album…'));
    final ignored = _ignoredFolders(settings);
    final captures = <({File file, String game})>[];
    final games = await source
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    games.sort((left, right) => left.path.compareTo(right.path));
    for (final game in games) {
      final gameName = p.basename(game.path);
      if (ignored.contains(_folderKey(gameName))) {
        continue;
      }
      try {
        await for (final entity in game.list(followLinks: false)) {
          if (entity is File && isNintendoSwitchCapture(entity.path)) {
            captures.add((file: entity, game: gameName));
          }
        }
      } on FileSystemException catch (exception) {
        diagnosticLog.warning(
          '$name could not read "${game.path}".',
          category: 'source',
          error: exception,
        );
      }
    }
    captures.sort((left, right) => left.file.path.compareTo(right.file.path));
    return _importCaptures(captures, settings, onProgress);
  }

  Future<ImportResult> _collectFromConsole(
    AppSettings settings,
    ProgressCallback? onProgress,
  ) async {
    onProgress?.call(SourceProgress(message: 'Looking for a $name album…'));
    final device = await usbDeviceFinder.find(
      vendorId: nintendoVendorId,
      productId: albumProductId,
    );
    if (device == null) {
      return ImportResult.warning(
        name,
        'No $name is currently sharing its album. On the console, open Album, choose Copy to a Computer, and connect it by USB.',
      );
    }

    try {
      await mtpClient.ensureAvailable();
      onProgress?.call(SourceProgress(message: 'Reading $name album folders…'));
      final folders = await mtpClient.folders();
      final files = await mtpClient.files();
      final stage = await Directory.systemTemp.createTemp(
        'gaming_memories_${id}_',
      );
      try {
        final plan = _planConsoleCollection(folders, files, stage, settings);
        if (plan.pulls.isEmpty) {
          return ImportResult(source: name, imported: 0, skipped: plan.skipped);
        }

        onProgress?.call(
          SourceProgress(
            message: 'Copying $name captures over USB…',
            completed: 0,
            total: plan.pulls.length,
          ),
        );
        await mtpClient.pull(
          plan.pulls,
          onProgress: (completed, total) => onProgress?.call(
            SourceProgress(
              message: 'Copying $name captures over USB…',
              completed: completed,
              total: total,
            ),
          ),
        );
        final result = await _importCaptures(
          plan.captures,
          settings,
          onProgress,
        );
        return ImportResult(
          source: name,
          imported: result.imported,
          skipped: result.skipped + plan.skipped,
        );
      } finally {
        try {
          await stage.delete(recursive: true);
        } on FileSystemException catch (exception) {
          diagnosticLog.warning(
            '$name could not remove staging folder "${stage.path}".',
            category: 'source',
            error: exception,
          );
        }
      }
    } on MtpException catch (exception) {
      diagnosticLog.warning(
        '$name MTP transfer failed.',
        category: 'source',
        error: exception,
      );
      final warning = _mtpWarning(exception);
      if (warning != null) {
        return ImportResult.warning(name, warning);
      }
      rethrow;
    }
  }

  _ConsolePlan _planConsoleCollection(
    List<MtpFolder> folders,
    List<MtpFile> files,
    Directory stage,
    AppSettings settings,
  ) {
    final ignored = _ignoredFolders(settings);
    final gameNames = <String, String>{
      for (final folder in folders)
        if (!ignored.contains(_folderKey(folder.name))) folder.id: folder.name,
    };
    final pulls = <MtpPull>[];
    final captures = <({File file, String game})>[];
    var skipped = 0;
    for (final remote in files) {
      final gameName = gameNames[remote.parentId];
      if (gameName == null || !isNintendoSwitchCapture(remote.name)) {
        continue;
      }
      final fileName = _destinationFileName(remote.name);
      final destination = File(
        p.join(
          expandUserPath(settings.outputPath.trim()),
          name,
          _safeGameName(gameName),
          fileName,
        ),
      );
      if (destination.existsSync()) {
        skipped++;
        continue;
      }
      final staged = File(p.join(stage.path, remote.parentId, fileName));
      pulls.add(MtpPull(file: remote, path: staged.path));
      captures.add((file: staged, game: gameName));
    }
    return _ConsolePlan(pulls: pulls, captures: captures, skipped: skipped);
  }

  Future<ImportResult> _importCaptures(
    List<({File file, String game})> captures,
    AppSettings settings,
    ProgressCallback? onProgress,
  ) async {
    var imported = 0;
    var skipped = 0;
    for (var index = 0; index < captures.length; index++) {
      final capture = captures[index];
      onProgress?.call(
        SourceProgress(
          message: 'Importing $name captures…',
          completed: index,
          total: captures.length,
        ),
      );
      final destination = Directory(
        p.join(
          expandUserPath(settings.outputPath.trim()),
          name,
          _safeGameName(capture.game),
        ),
      );
      final copied = await importer.copyWithName(
        capture.file,
        destination,
        baseName: p.basenameWithoutExtension(capture.file.path),
      );
      if (copied) {
        imported++;
      } else {
        skipped++;
      }
    }
    onProgress?.call(
      SourceProgress(
        message: 'Processed $name captures.',
        completed: captures.length,
        total: captures.length,
      ),
    );
    return ImportResult(source: name, imported: imported, skipped: skipped);
  }

  Set<String> _ignoredFolders(AppSettings settings) =>
      config(settings).ignoredFolders
          .map(_folderKey)
          .where((folder) => folder.isNotEmpty)
          .toSet();

  String _safeGameName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
        ? 'Unknown $name game'
        : cleaned;
  }

  String? _mtpWarning(MtpException exception) => switch (exception.failure) {
    MtpFailure.busy =>
      '$name could not be read because another app is using it. Eject it from the file manager, close that app, and try again.',
    MtpFailure.staleSession =>
      '$name kept an old USB session open. Unplug it, reconnect it, share the album again, and retry.',
    MtpFailure.noDevice =>
      '$name stopped sharing its album. Share the album again on the console and retry.',
    MtpFailure.missingTools =>
      '$name USB collection requires the libmtp tools: mtp-folders, mtp-files, and mtp-connect. Install libmtp or select a copied album folder in Settings.',
    MtpFailure.command || MtpFailure.incompleteTransfer => null,
  };
}

/// The console writes an original `_s` capture and, for a capture it has
/// shared, a `_c` copy beside it. Only the originals are worth importing.
bool isNintendoSwitchCapture(String path) {
  final name = p.basename(path);
  final extension = p.extension(name).toLowerCase();
  return const {'.jpg', '.mp4'}.contains(extension) &&
      p.basenameWithoutExtension(name).endsWith('_s');
}

String _destinationFileName(String name) =>
    '${p.basenameWithoutExtension(p.basename(name))}${p.extension(name).toLowerCase()}';

String _folderKey(String value) => value.trim().toLowerCase();

class _ConsolePlan {
  const _ConsolePlan({
    required this.pulls,
    required this.captures,
    required this.skipped,
  });

  final List<MtpPull> pulls;
  final List<({File file, String game})> captures;
  final int skipped;
}
