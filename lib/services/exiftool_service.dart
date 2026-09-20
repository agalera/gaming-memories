import 'dart:io';

abstract interface class ExifDateReader {
  Future<void> ensureAvailable();

  Future<DateTime> fileModifiedAt(File file);
}

class ExifToolDateReader implements ExifDateReader {
  const ExifToolDateReader();

  @override
  Future<void> ensureAvailable() async {
    try {
      final result = await Process.run('exiftool', ['-ver']);
      if (result.exitCode != 0) {
        throw const FileSystemException(
          'ExifTool is required. Install exiftool and add it to PATH.',
        );
      }
    } on ProcessException {
      throw const FileSystemException(
        'ExifTool is required. Install exiftool and add it to PATH.',
      );
    }
  }

  @override
  Future<DateTime> fileModifiedAt(File file) async {
    ProcessResult result;
    try {
      result = await Process.run('exiftool', [
        '-FileModifyDate',
        '-s3',
        file.path,
      ]);
    } on ProcessException catch (exception) {
      throw FileSystemException(
        'ExifTool could not read the screenshot date: $exception',
        file.path,
      );
    }

    if (result.exitCode != 0) {
      final detail = result.stderr.toString().trim();
      throw FileSystemException(
        detail.isEmpty
            ? 'ExifTool could not read the screenshot date.'
            : 'ExifTool could not read the screenshot date: $detail',
        file.path,
      );
    }

    final value = result.stdout.toString().trim();
    final date = parseExifToolDate(value);
    if (date == null) {
      throw FileSystemException(
        'ExifTool returned an invalid FileModifyDate value: $value',
        file.path,
      );
    }
    return date;
  }
}

DateTime? parseExifToolDate(String value) {
  final match = RegExp(
    r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})(?:[+-]\d{2}:\d{2}|Z)?$',
  ).firstMatch(value.trim());
  if (match == null) {
    return null;
  }

  final parts = [
    for (var index = 1; index <= 6; index++) int.parse(match[index]!),
  ];
  final date = DateTime(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (date.year != parts[0] ||
      date.month != parts[1] ||
      date.day != parts[2] ||
      date.hour != parts[3] ||
      date.minute != parts[4] ||
      date.second != parts[5]) {
    return null;
  }

  return date;
}
