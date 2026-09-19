import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

abstract interface class ByteCache {
  Future<List<int>?> get(String key, Duration maximumAge);
  Future<void> set(String key, List<int> value);
}

class FileCache implements ByteCache {
  const FileCache(this.directory);

  final Directory directory;

  @override
  Future<List<int>?> get(String key, Duration maximumAge) async {
    final file = _file(key);
    if (!await file.exists()) {
      return null;
    }

    final stat = await file.stat();
    if (DateTime.now().difference(stat.modified) > maximumAge) {
      return null;
    }

    return file.readAsBytes();
  }

  @override
  Future<void> set(String key, List<int> value) async {
    await directory.create(recursive: true);
    await _file(key).writeAsBytes(value, flush: true);
  }

  File _file(String key) {
    final digest = sha1.convert(key.codeUnits);
    return File(p.join(directory.path, '$digest.cache'));
  }
}
