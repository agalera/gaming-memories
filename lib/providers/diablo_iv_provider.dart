import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../services/library_scanner.dart';

class ImportResult {
  const ImportResult({required this.imported, required this.skipped});

  const ImportResult.empty() : imported = 0, skipped = 0;

  final int imported;
  final int skipped;
}

class DiabloIVProvider {
  const DiabloIVProvider();

  static const id = 'diablo_4';
  static const name = 'Diablo IV';
  static const platform = 'PC';
  static const _extensions = {'.jpg', '.jpeg', '.png'};

  Future<ImportResult> collect(AppSettings settings) async {
    if (!settings.diabloIV.enabled) {
      return const ImportResult.empty();
    }

    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      throw const FileSystemException('Select a library folder first.');
    }

    final sourceDirectories = _sourceDirectories(settings.diabloIV.sourcePath);
    if (sourceDirectories.isEmpty) {
      throw const FileSystemException(
        'Select a Diablo IV screenshot folder on this platform.',
      );
    }

    final destination = Directory(
      p.join(expandUserPath(outputPath), platform, name),
    );
    await destination.create(recursive: true);

    var imported = 0;
    var skipped = 0;

    for (final sourceDirectory in sourceDirectories) {
      if (!await sourceDirectory.exists()) {
        continue;
      }

      final files = await sourceDirectory
          .list(followLinks: false)
          .where((entity) => entity is File && _isScreenshot(entity.path))
          .cast<File>()
          .toList();
      files.sort((left, right) => left.path.compareTo(right.path));

      for (final source in files) {
        final copied = await _copyScreenshot(source, destination);
        if (copied) {
          imported++;
        } else {
          skipped++;
        }
      }
    }

    return ImportResult(imported: imported, skipped: skipped);
  }

  List<Directory> _sourceDirectories(String configuredPath) {
    final path = configuredPath.trim();
    if (path.isNotEmpty && path != 'auto') {
      return [Directory(expandUserPath(path))];
    }

    if (!Platform.isWindows) {
      return const [];
    }

    final home = homeDirectory();
    if (home == null) {
      return const [];
    }

    return [
      Directory(p.join(home, 'Pictures', 'Diablo IV')),
      Directory(p.join(home, 'Documents', 'Diablo IV', 'Screenshots')),
    ];
  }

  bool _isScreenshot(String path) {
    return _extensions.contains(p.extension(path).toLowerCase());
  }

  Future<bool> _copyScreenshot(File source, Directory destination) async {
    final stat = await source.stat();
    final extension = p.extension(source.path).toLowerCase();
    final baseName = _formatDate(stat.modified);
    var target = File(p.join(destination.path, '$baseName$extension'));

    if (await target.exists()) {
      final sourceHash = await _hash(source);
      if (sourceHash == await _hash(target)) {
        return false;
      }

      target = File(
        p.join(destination.path, '${baseName}_$sourceHash$extension'),
      );
      if (await target.exists() && sourceHash == await _hash(target)) {
        return false;
      }
    }

    await source.copy(target.path);
    await target.setLastModified(stat.modified);
    return true;
  }

  Future<String> _hash(File file) async {
    return (await sha1.bind(file.openRead()).first).toString();
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');

    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-${two(value.day)}_'
        '${two(value.hour)}-${two(value.minute)}-${two(value.second)}';
  }
}
