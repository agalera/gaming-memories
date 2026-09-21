import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/folder_access_service.dart';

const _request = FolderAccessRequest(
  id: FolderGrantIds.library,
  title: 'Choose the media library folder',
  access: FolderGrantAccess.readWrite,
  initialPath: '/Users/alice/Pictures',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('gaming-memories/folder-access');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('the path service leases the chosen folder', () async {
    late FolderAccessRequest seen;
    final service = PathFolderAccessService(
      chooseDirectory: (request) async {
        seen = request;
        return '/Users/alice/Pictures/Gaming Memories';
      },
    );

    final lease = await service.choose(_request);

    expect(seen.title, _request.title);
    expect(seen.initialPath, _request.initialPath);
    expect(lease!.grant.path, '/Users/alice/Pictures/Gaming Memories');
    expect(lease.grant.access, FolderGrantAccess.readWrite);
    expect(lease.grant.platform, Platform.operatingSystem);
  });

  test(
    'the path service leases nothing when the chooser is dismissed',
    () async {
      const service = PathFolderAccessService(chooseDirectory: _dismiss);

      expect(await service.choose(_request), isNull);
    },
  );

  test('the macOS chooser asks the Runner for a folder path', () async {
    MethodCall? call;
    messenger.setMockMethodCallHandler(channel, (invocation) async {
      call = invocation;
      return '/Users/alice/Pictures/Gaming Memories';
    });

    final selected = await chooseDirectoryWithOpenPanel(_request);

    expect(selected, '/Users/alice/Pictures/Gaming Memories');
    expect(call!.method, 'choosePath');
    expect(call!.arguments, {
      'title': _request.title,
      'initialPath': _request.initialPath,
      'readOnly': false,
    });
  });

  test('the macOS chooser reports a dismissed panel', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    expect(await chooseDirectoryWithOpenPanel(_request), isNull);
  });

  test('the macOS chooser surfaces a Runner failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'chooserBusy', message: 'Already open.');
    });

    await expectLater(
      chooseDirectoryWithOpenPanel(_request),
      throwsA(
        isA<FolderAccessException>()
            .having((error) => error.code, 'code', 'chooserBusy')
            .having((error) => error.message, 'message', 'Already open.'),
      ),
    );
  });

  test('the macOS Runner answers the folder path call', () {
    final runner = File('macos/Runner/MainFlutterWindow.swift')
        .readAsStringSync();

    expect(runner, contains('case "choosePath":'));
  });
}

Future<String?> _dismiss(FolderAccessRequest request) async => null;
