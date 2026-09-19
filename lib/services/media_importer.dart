import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class MediaImporter {
  const MediaImporter();

  Future<bool> copyByModifiedDate(File source, Directory destination) async {
    final stat = await source.stat();
    final bytes = await source.readAsBytes();
    final result = await _write(
      bytes,
      destination,
      baseName: formatDate(stat.modified),
      extension: p.extension(source.path).toLowerCase(),
    );

    if (result.imported) {
      await result.target.setLastModified(stat.modified);
    }

    return result.imported;
  }

  Future<bool> writeBytes(
    List<int> bytes,
    Directory destination, {
    required String baseName,
    required String extension,
  }) async {
    final result = await _write(
      bytes,
      destination,
      baseName: baseName,
      extension: extension.toLowerCase(),
    );
    return result.imported;
  }

  Future<({bool imported, File target})> _write(
    List<int> bytes,
    Directory destination, {
    required String baseName,
    required String extension,
  }) async {
    await destination.create(recursive: true);
    final digest = sha1.convert(bytes).toString();
    final first = File(p.join(destination.path, '$baseName$extension'));

    if (!await first.exists()) {
      await first.writeAsBytes(bytes, flush: true);
      return (imported: true, target: first);
    }

    if (await _hasDigest(first, digest)) {
      return (imported: false, target: first);
    }

    final collision = File(
      p.join(destination.path, '${baseName}_$digest$extension'),
    );
    if (await collision.exists()) {
      if (await _hasDigest(collision, digest)) {
        return (imported: false, target: collision);
      }

      throw FileSystemException(
        'A file exists with the same content hash but different content.',
        collision.path,
      );
    }

    await collision.writeAsBytes(bytes, flush: true);
    return (imported: true, target: collision);
  }

  Future<bool> _hasDigest(File file, String digest) async {
    return sha1.convert(await file.readAsBytes()).toString() == digest;
  }
}

String formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');

  return '${value.year.toString().padLeft(4, '0')}-'
      '${two(value.month)}-${two(value.day)}_'
      '${two(value.hour)}-${two(value.minute)}-${two(value.second)}';
}
