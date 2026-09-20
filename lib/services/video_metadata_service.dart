import 'dart:convert';
import 'dart:io';

class VideoMetadataService {
  const VideoMetadataService();

  String pathFor(String sourcePath) => '$sourcePath.metadata.json';

  Future<Duration?> ensureDuration(File source, FileStat sourceStat) async {
    final metadata = File(pathFor(source.path));
    final cached = await _readDuration(metadata);

    try {
      if (cached != null && await _isCurrent(metadata, sourceStat)) {
        return cached;
      }

      final result = await Process.run('ffprobe', [
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        source.path,
      ]);
      if (result.exitCode != 0) {
        return cached;
      }

      final seconds = double.tryParse(result.stdout.toString().trim());
      if (seconds == null || !seconds.isFinite || seconds < 0) {
        return cached;
      }

      await _writeMetadata(metadata, seconds);
      return Duration(milliseconds: (seconds * 1000).round());
    } on FileSystemException {
      return cached;
    } on ProcessException {
      return cached;
    } on FormatException {
      return cached;
    }
  }

  Future<bool> _isCurrent(File metadata, FileStat sourceStat) async {
    if (!await metadata.exists()) {
      return false;
    }

    final metadataStat = await metadata.stat();
    return metadataStat.size > 0 &&
        !metadataStat.modified.isBefore(sourceStat.modified);
  }

  Future<Duration?> _readDuration(File metadata) async {
    try {
      if (!await metadata.exists()) {
        return null;
      }

      final value = jsonDecode(await metadata.readAsString());
      if (value is! Map<String, dynamic>) {
        return null;
      }

      final seconds = switch (value['duration']) {
        num duration => duration.toDouble(),
        String duration => double.tryParse(duration),
        _ => null,
      };
      if (seconds == null || !seconds.isFinite || seconds < 0) {
        return null;
      }

      return Duration(milliseconds: (seconds * 1000).round());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeMetadata(File metadata, double seconds) async {
    final temporary = File('${metadata.path}.tmp');
    final value = <String, Object>{
      'ffmpeg_metadata': seconds.toString(),
      'duration': seconds,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(value),
        flush: true,
      );
      if (await metadata.exists()) {
        await metadata.delete();
      }
      await temporary.rename(metadata.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }
}
