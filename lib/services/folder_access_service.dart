import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';

abstract final class FolderGrantIds {
  static const library = 'library';
  static const battleNet = 'source.battleNet';
  static const guildWars2 = 'source.guildWars2';
  static const hytale = 'source.hytale';
  static const minecraft = 'source.minecraft';
  static const nintendoSwitch = 'source.nintendoSwitch';
  static const nintendoSwitch2 = 'source.nintendoSwitch2';
  static const playStation4 = 'source.playStation4';
  static const playStation5 = 'source.playStation5';
  static const steam = 'source.steam';
}

class FolderAccessRequest {
  const FolderAccessRequest({
    required this.id,
    required this.title,
    required this.access,
    this.initialPath,
    this.suggestedPath,
    this.message,
  });

  final String id;
  final String title;
  final FolderGrantAccess access;
  final String? initialPath;
  final String? suggestedPath;
  final String? message;
}

class FolderAccessLease {
  const FolderAccessLease({required this.grant, required this.token});

  final FolderGrant grant;
  final String token;
}

class FolderAccessException implements Exception {
  const FolderAccessException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// What a file chooser is opened for.
class FileChoiceRequest {
  const FileChoiceRequest({
    required this.title,
    this.initialPath,
    this.showHiddenFiles = false,
  });

  final String title;
  final String? initialPath;

  /// SSH keys live in `~/.ssh`, which a chooser hides unless asked.
  final bool showHiddenFiles;
}

abstract interface class FolderAccessService {
  bool get requiresPersistentGrant;

  Future<FolderAccessLease?> choose(FolderAccessRequest request);

  /// Opens a file chooser and returns the selected path, or null when it was
  /// dismissed.
  Future<String?> chooseFile(FileChoiceRequest request);

  Future<FolderAccessLease> activate(FolderGrant grant);

  Future<void> release(FolderAccessLease lease);

  Future<void> dispose();
}

/// Opens a folder chooser for [request] and returns the selected path, or null
/// when the chooser was dismissed.
typedef DirectoryChooser = Future<String?> Function(
  FolderAccessRequest request,
);

const _folderAccessChannel = MethodChannel('gaming-memories/folder-access');

Future<String?> chooseDirectoryWithFilePicker(FolderAccessRequest request) {
  return FilePicker.getDirectoryPath(
    dialogTitle: request.title,
    initialDirectory: request.initialPath,
  );
}

/// Opens a file chooser for [request] and returns the selected path, or null
/// when it was dismissed.
typedef FileChooser = Future<String?> Function(FileChoiceRequest request);

Future<String?> chooseFileWithFilePicker(FileChoiceRequest request) async {
  final picked = await FilePicker.pickFile(
    dialogTitle: request.title,
    initialDirectory: request.initialPath,
  );
  return picked?.path;
}

// The same entitlement problem as the folder chooser, and the same answer:
// the Runner's own panel. It can also be told to show hidden files, which
// file_picker cannot, and without that `~/.ssh` is out of reach.
Future<String?> chooseFileWithOpenPanel(FileChoiceRequest request) async {
  try {
    return await _folderAccessChannel.invokeMethod<String>('chooseFile', {
      'title': request.title,
      'initialPath': request.initialPath,
      'showHiddenFiles': request.showHiddenFiles,
    });
  } on PlatformException catch (error) {
    throw FolderAccessException(
      error.code,
      error.message ?? 'macOS could not open the file chooser.',
    );
  }
}

// file_picker refuses to open its macOS panel unless the app declares the App
// Sandbox `com.apple.security.files.user-selected` entitlements, and it drops
// the dialog title and the initial directory there. The Runner owns an
// NSOpenPanel that honours both and needs no entitlement.
Future<String?> chooseDirectoryWithOpenPanel(
  FolderAccessRequest request,
) async {
  try {
    return await _folderAccessChannel.invokeMethod<String>('choosePath', {
      'title': request.title,
      'initialPath': request.initialPath,
      'readOnly': request.access == FolderGrantAccess.readOnly,
    });
  } on PlatformException catch (error) {
    throw FolderAccessException(
      error.code,
      error.message ?? 'macOS could not open the folder chooser.',
    );
  }
}

// The macOS release build is distributed with Developer ID and runs outside
// the App Sandbox, so it can start ffmpeg and ffprobe. Security
// scoped bookmarks are a sandbox facility and cannot be created there, and
// outside the sandbox a plain path carries the same access, so every platform
// uses the path service.
FolderAccessService createFolderAccessService() {
  return PathFolderAccessService(
    chooseDirectory: Platform.isMacOS
        ? chooseDirectoryWithOpenPanel
        : chooseDirectoryWithFilePicker,
    chooseFilePath: Platform.isMacOS
        ? chooseFileWithOpenPanel
        : chooseFileWithFilePicker,
  );
}

class PathFolderAccessService implements FolderAccessService {
  const PathFolderAccessService({
    this.chooseDirectory = chooseDirectoryWithFilePicker,
    this.chooseFilePath = chooseFileWithFilePicker,
  });

  final DirectoryChooser chooseDirectory;
  final FileChooser chooseFilePath;

  @override
  Future<String?> chooseFile(FileChoiceRequest request) =>
      chooseFilePath(request);

  @override
  bool get requiresPersistentGrant => false;

  @override
  Future<FolderAccessLease?> choose(FolderAccessRequest request) async {
    final selected = await chooseDirectory(request);
    if (selected == null) {
      return null;
    }

    return FolderAccessLease(
      grant: FolderGrant(
        platform: Platform.operatingSystem,
        path: selected,
        access: request.access,
        bookmark: '',
      ),
      token: '',
    );
  }

  @override
  Future<FolderAccessLease> activate(FolderGrant grant) async {
    return FolderAccessLease(grant: grant, token: '');
  }

  @override
  Future<void> release(FolderAccessLease lease) async {}

  @override
  Future<void> dispose() async {}
}

// The service a sandboxed macOS build needs: inside the App Sandbox a path is
// not a credential, so every folder is reached through a security scoped
// bookmark taken from the panel selection.
class MacOSFolderAccessService implements FolderAccessService {
  const MacOSFolderAccessService();

  static const _channel = _folderAccessChannel;

  @override
  bool get requiresPersistentGrant => true;

  @override
  Future<String?> chooseFile(FileChoiceRequest request) =>
      chooseFileWithOpenPanel(request);

  @override
  Future<FolderAccessLease?> choose(FolderAccessRequest request) async {
    try {
      final result = await _channel.invokeMethod<Object?>('choose', {
        'id': request.id,
        'title': request.title,
        'initialPath': request.initialPath,
        'suggestedPath': request.suggestedPath,
        'message': request.message,
        'readOnly': request.access == FolderGrantAccess.readOnly,
      });
      if (result == null) {
        return null;
      }
      return _leaseFromResult(result, request.access);
    } on PlatformException catch (error) {
      throw FolderAccessException(
        error.code,
        error.message ?? 'macOS could not grant access to that folder.',
      );
    }
  }

  @override
  Future<FolderAccessLease> activate(FolderGrant grant) async {
    try {
      final result = await _channel.invokeMethod<Object?>('activate', {
        'bookmark': Uint8List.fromList(base64Decode(grant.bookmark)),
        'readOnly': grant.access == FolderGrantAccess.readOnly,
      });
      return _leaseFromResult(result, grant.access);
    } on FormatException {
      throw const FolderAccessException(
        'bookmarkInvalid',
        'The saved folder permission is invalid.',
      );
    } on PlatformException catch (error) {
      throw FolderAccessException(
        error.code,
        error.message ?? 'macOS could not restore access to that folder.',
      );
    }
  }

  FolderAccessLease _leaseFromResult(Object? result, FolderGrantAccess access) {
    if (result is! Map) {
      throw const FolderAccessException(
        'invalidResponse',
        'macOS returned an invalid folder permission.',
      );
    }
    final path = result['path'];
    final token = result['leaseId'];
    final bookmark = result['bookmark'];
    if (path is! String ||
        token is! String ||
        bookmark is! Uint8List ||
        path.isEmpty ||
        token.isEmpty) {
      throw const FolderAccessException(
        'invalidResponse',
        'macOS returned an incomplete folder permission.',
      );
    }

    return FolderAccessLease(
      grant: FolderGrant(
        platform: 'macos',
        path: path,
        access: access,
        bookmark: base64Encode(bookmark),
      ),
      token: token,
    );
  }

  @override
  Future<void> release(FolderAccessLease lease) async {
    if (lease.token.isEmpty) {
      return;
    }
    await _channel.invokeMethod<void>('release', {'leaseId': lease.token});
  }

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod<void>('releaseAll');
  }
}
