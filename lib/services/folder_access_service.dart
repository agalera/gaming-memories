import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';

abstract final class FolderGrantIds {
  static const library = 'library';
  static const diabloIV = 'provider.diabloIV';
  static const guildWars2 = 'provider.guildWars2';
  static const hytale = 'provider.hytale';
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

FolderAccessService createFolderAccessService() {
  return Platform.isMacOS
      ? const MacOSFolderAccessService()
      : const PathFolderAccessService();
}

class PathFolderAccessService implements FolderAccessService {
  const PathFolderAccessService();

  @override
  bool get requiresPersistentGrant => false;

  @override
  Future<FolderAccessLease?> choose(FolderAccessRequest request) async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: request.title,
      initialDirectory: request.initialPath,
    );
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

class MacOSFolderAccessService implements FolderAccessService {
  const MacOSFolderAccessService();

  static const _channel = MethodChannel('gaming-memories/folder-access');

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
