import 'dart:async';
import 'dart:io';

import 'folder_access_service.dart';

/// Turns a thrown object into a sentence a person can act on.
///
/// Nothing here repeats the exception. `FileSystemException: Directory listing
/// failed, path = '/Users/x' (OS Error: Operation not permitted, errno = 1)`
/// tells the user nothing they can use, and the same text is already on its
/// way to the log file, which is where it belongs.
///
/// [action] names what the app was doing, in the second person and without a
/// trailing full stop — "load the library", "save your settings".
String describeFailure(Object failure, {required String action}) {
  final reason = _reason(failure);
  return reason == null
      ? 'Could not $action. The details were written to the log file.'
      : 'Could not $action. $reason';
}

/// The part of the message that explains what went wrong, or null when the
/// failure says nothing worth passing on.
String? _reason(Object failure) {
  // Messages the app wrote itself are already meant for the user.
  if (failure is FolderAccessException) {
    return _sentence(failure.message);
  }
  if (failure is PathAccessException) {
    return 'The app is not allowed to open that folder. Grant access to it in Settings.';
  }
  if (failure is PathNotFoundException) {
    return 'The folder or file is no longer there. It may have been moved, renamed or unplugged.';
  }
  if (failure is FileSystemException) {
    return _fileSystemReason(failure);
  }
  if (failure is SocketException || failure is HttpException) {
    return 'The app could not reach the network. Check your connection and try again.';
  }
  if (failure is TimeoutException) {
    return 'The request took too long to answer. Try again in a moment.';
  }
  if (failure is FormatException) {
    return 'A file was not in the format the app expected, so it may be damaged.';
  }
  return null;
}

String? _fileSystemReason(FileSystemException failure) {
  final code = failure.osError?.errorCode;
  final reason = switch (code) {
    // EACCES / EPERM, and Windows ERROR_ACCESS_DENIED.
    1 || 13 || 5 => 'The app is not allowed to read that folder. Grant access to it in Settings.',
    // ENOENT, and Windows ERROR_FILE_NOT_FOUND / ERROR_PATH_NOT_FOUND.
    2 || 3 => 'The folder or file is no longer there. It may have been moved, renamed or unplugged.',
    // ENOSPC, and Windows ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL.
    28 || 39 || 112 => 'The disk is full. Free some space and try again.',
    // EROFS, and Windows ERROR_WRITE_PROTECT.
    30 || 19 => 'That location is read-only, so nothing can be written to it.',
    // ENOTDIR / EISDIR.
    20 || 21 => 'That path is not the kind of item the app expected.',
    _ => null,
  };
  if (reason != null) {
    return reason;
  }
  // A message the app raised itself carries no OS error and is written for
  // the user; one from the platform is not worth repeating.
  return failure.osError == null ? _sentence(failure.message) : null;
}

String? _sentence(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed.endsWith('.') || trimmed.endsWith('!') || trimmed.endsWith('?')
      ? trimmed
      : '$trimmed.';
}
