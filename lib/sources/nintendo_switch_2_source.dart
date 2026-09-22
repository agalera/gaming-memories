import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/folder_access_service.dart';
import '../services/app_log.dart';
import '../services/library_scanner.dart';
import '../services/media_importer.dart';
import '../services/mtp_client.dart';
import 'screenshot_source.dart';

class NintendoSwitch2Source
    with SingleFolderRequirement
    implements FolderBackedScreenshotSource {
  const NintendoSwitch2Source({
    this.importer = const MediaImporter(),
    this.mtpClient = const LibMtpClient(),
    this.usbDeviceFinder = const LinuxSysfsUsbDeviceFinder(),
    this.operatingSystem,
  });

  final MediaImporter importer;
  final MtpClient mtpClient;
  final UsbDeviceFinder usbDeviceFinder;
  final String? operatingSystem;

  static const id = 'nintendo_switch_2';
  static const platform = 'Nintendo Switch 2';
  static const _nintendoVendorId = '057e';
  static const _albumProductId = '2061';

  @override
  String get name => platform;

  @override
  String get folderGrantId => FolderGrantIds.nintendoSwitch2;

  @override
  bool isEnabled(AppSettings settings) => settings.nintendoSwitch2.enabled;

  @override
  SourceFolderRequirement? folderRequirement(AppSettings settings) {
    final config = settings.nintendoSwitch2;
    if (!config.useCustomPath || config.sourcePath.trim().isEmpty) {
      return null;
    }
    return SourceFolderRequirement(
      id: folderGrantId,
      path: expandUserPath(config.sourcePath.trim()),
      automatic: false,
    );
  }

  @override
  AppSettings withFolderPath(AppSettings settings, String path) {
    return settings.copyWith(
      nintendoSwitch2: settings.nintendoSwitch2.copyWith(
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
    if (!settings.nintendoSwitch2.enabled) {
      return ImportResult.empty(name);
    }
    if (settings.outputPath.trim().isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    final config = settings.nintendoSwitch2;
    if (config.useCustomPath) {
      final sourcePath = config.sourcePath.trim();
      if (sourcePath.isEmpty) {
        throw const FileSystemException(
          'Choose a copied Nintendo Switch 2 album folder in Settings.',
        );
      }
      return _collectFromFolder(
        Directory(expandUserPath(sourcePath)),
        settings,
        onProgress,
      );
    }

    if ((operatingSystem ?? Platform.operatingSystem) != 'linux') {
      return const ImportResult.warning(
        platform,
        'Nintendo Switch 2 direct USB collection is available on Linux. Select a copied album folder in Settings on this computer.',
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
        'The selected Nintendo Switch 2 album folder does not exist.',
        source.path,
      );
    }

    onProgress?.call(
      const SourceProgress(message: 'Scanning Nintendo Switch 2 album…'),
    );
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
          if (entity is File && isNintendoSwitch2Capture(entity.path)) {
            captures.add((file: entity, game: gameName));
          }
        }
      } on FileSystemException catch (exception) {
        diagnosticLog.warning(
          'Nintendo Switch 2 could not read "${game.path}".',
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
    onProgress?.call(
      const SourceProgress(message: 'Looking for a Nintendo Switch 2 album…'),
    );
    final device = await usbDeviceFinder.find(
      vendorId: _nintendoVendorId,
      productId: _albumProductId,
    );
    if (device == null) {
      return const ImportResult.warning(
        platform,
        'No Nintendo Switch 2 is currently sharing its album. On the console, open Album, choose Copy to a Computer, and connect it by USB.',
      );
    }

    try {
      await mtpClient.ensureAvailable();
      onProgress?.call(
        const SourceProgress(
          message: 'Reading Nintendo Switch 2 album folders…',
        ),
      );
      final folders = await mtpClient.folders();
      final files = await mtpClient.files();
      final stage = await Directory.systemTemp.createTemp(
        'gaming_memories_switch2_',
      );
      try {
        final plan = _planConsoleCollection(folders, files, stage, settings);
        if (plan.pulls.isEmpty) {
          return ImportResult(source: name, imported: 0, skipped: plan.skipped);
        }

        onProgress?.call(
          SourceProgress(
            message: 'Copying Nintendo Switch 2 captures over USB…',
            completed: 0,
            total: plan.pulls.length,
          ),
        );
        await mtpClient.pull(
          plan.pulls,
          onProgress: (completed, total) => onProgress?.call(
            SourceProgress(
              message: 'Copying Nintendo Switch 2 captures over USB…',
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
            'Nintendo Switch 2 could not remove staging folder "${stage.path}".',
            category: 'source',
            error: exception,
          );
        }
      }
    } on MtpException catch (exception) {
      diagnosticLog.warning(
        'Nintendo Switch 2 MTP transfer failed.',
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
      if (gameName == null || !isNintendoSwitch2Capture(remote.name)) {
        continue;
      }
      final fileName = _destinationFileName(remote.name);
      final destination = File(
        p.join(
          expandUserPath(settings.outputPath.trim()),
          platform,
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
          message: 'Importing Nintendo Switch 2 captures…',
          completed: index,
          total: captures.length,
        ),
      );
      final destination = Directory(
        p.join(
          expandUserPath(settings.outputPath.trim()),
          platform,
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
        message: 'Processed Nintendo Switch 2 captures.',
        completed: captures.length,
        total: captures.length,
      ),
    );
    return ImportResult(source: name, imported: imported, skipped: skipped);
  }

  Set<String> _ignoredFolders(AppSettings settings) => settings
      .nintendoSwitch2
      .ignoredFolders
      .map(_folderKey)
      .where((name) => name.isNotEmpty)
      .toSet();

  String? _mtpWarning(MtpException exception) => switch (exception.failure) {
    MtpFailure.busy => 'Nintendo Switch 2 could not be read because another app is using it. Eject it from the file manager, close that app, and try again.',
    MtpFailure.staleSession => 'Nintendo Switch 2 kept an old USB session open. Unplug it, reconnect it, share the album again, and retry.',
    MtpFailure.noDevice => 'Nintendo Switch 2 stopped sharing its album. Share the album again on the console and retry.',
    MtpFailure.missingTools => 'Nintendo Switch 2 USB collection requires the libmtp tools: mtp-folders, mtp-files, and mtp-connect. Install libmtp or select a copied album folder in Settings.',
    MtpFailure.command || MtpFailure.incompleteTransfer => null,
  };
}

bool isNintendoSwitch2Capture(String path) {
  final name = p.basename(path);
  final extension = p.extension(name).toLowerCase();
  return const {'.jpg', '.mp4'}.contains(extension) &&
      p.basenameWithoutExtension(name).endsWith('_s');
}

String _destinationFileName(String name) =>
    '${p.basenameWithoutExtension(p.basename(name))}${p.extension(name).toLowerCase()}';

String _folderKey(String value) => value.trim().toLowerCase();

String _safeGameName(String value) {
  final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
      ? 'Unknown Nintendo Switch 2 game'
      : cleaned;
}

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
