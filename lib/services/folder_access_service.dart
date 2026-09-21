import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';

abstract final class FolderGrantIds {
  static const library = 'library';
  static const battleNet = 'provider.battleNet';
  static const guildWars2 = 'provider.guildWars2';
  static const hytale = 'provider.hytale';
  static const minecraft = 'provider.minecraft';
  static const nintendoSwitch2 = 'provider.nintendoSwitch2';
  static const playStation4 = 'provider.playStation4';
  static const playStation5 = 'provider.playStation5';
  static const steam = 'provider.steam';
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

abstract interface class FolderAccessService {
  bool get requiresPersistentGrant;

  Future<FolderAccessLease?> choose(FolderAccessRequest request);

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
  );
}

class PathFolderAccessService implements FolderAccessService {
  const PathFolderAccessService({
    this.chooseDirectory = chooseDirectoryWithFilePicker,
  });

  final DirectoryChooser chooseDirectory;

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
