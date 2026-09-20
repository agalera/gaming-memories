import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/providers/steam_provider.dart';
import 'package:gaming_memories/services/steam_client.dart';
import 'package:path/path.dart' as p;

void main() {
  const validUserId = '76561198000000000';
  const validApiKey = '0123456789abcdef0123456789abcdef';
  late Directory steam;
  late Directory output;
  late _FakeSteamApi api;

  setUp(() async {
    steam = await Directory.systemTemp.createTemp('gaming-memories-steam-');
    output = await Directory.systemTemp.createTemp('gaming-memories-output-');
    api = _FakeSteamApi();
  });

  tearDown(() async {
    await steam.delete(recursive: true);
    await output.delete(recursive: true);
  });

  AppSettings settings({
    bool onlineGallery = false,
    bool downloadCovers = false,
    List<String> ignoredGames = const [],
    Map<String, String> customGames = const {},
  }) {
    return AppSettings(
      outputPath: output.path,
      steam: SteamSettings(
        enabled: true,
        useCustomPath: true,
        userdataPath: steam.path,
        onlineGallery: onlineGallery,
        userId: validUserId,
        apiKey: validApiKey,
        downloadCovers: downloadCovers,
        ignoredGames: ignoredGames,
        customGames: customGames,
      ),
    );
  }

  Future<File> addLocalScreenshot(String appId, String contents) async {
    final directory = Directory(
      p.join(
        steam.path,
        'userdata',
        '1',
        '760',
        'remote',
        appId,
        'screenshots',
      ),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'original.jpg'));
    await file.writeAsString(contents);
    await file.setLastModified(DateTime(2026, 6, 7, 8, 9, 10));
    return file;
  }

  test('imports local screenshots with a resolved game name', () async {
    await addLocalScreenshot('10', 'local');
    api.names['10'] = 'Test Game';

    final result = await SteamProvider(api: api).collect(settings());

    expect(result.imported, 1);
    expect(
      File(p.join(output.path, 'PC', 'Test Game', '2026-06-07_08-09-10.jpg'))
          .existsSync(),
      isTrue,
    );
  });

  test('rejects invalid Steam authentication', () async {
    api.credentialFailure = const FormatException(
      'Steam credentials are invalid.',
    );

    final error = await SteamProvider(api: api)
        .configurationError(settings(onlineGallery: true));

    expect(error, 'Steam credentials are invalid.');
  });

  test('requires an API key for local Steam imports', () async {
    final value = settings();

    final error = await SteamProvider(api: api).configurationError(
      value.copyWith(steam: value.steam.copyWith(apiKey: '')),
    );

    expect(error, 'Enter a Steam Web API key.');
    expect(api.validatedCredentials, isEmpty);
  });

  test('rejects an invalid API key format', () async {
    final value = settings();

    final error = await SteamProvider(api: api).configurationError(
      value.copyWith(steam: value.steam.copyWith(apiKey: 'invalid')),
    );

    expect(error, 'Enter a valid 32-character Steam Web API key.');
    expect(api.validatedCredentials, isEmpty);
  });

  test('requires a SteamID64 for online gallery imports', () async {
    final value = settings(onlineGallery: true);

    final error = await SteamProvider(api: api).configurationError(
      value.copyWith(steam: value.steam.copyWith(userId: '')),
    );

    expect(error, 'Enter a Steam user ID for online gallery imports.');
    expect(api.validatedCredentials, isEmpty);
  });

  test('rejects an invalid SteamID64 format', () async {
    final value = settings(onlineGallery: true);

    final error = await SteamProvider(api: api).configurationError(
      value.copyWith(steam: value.steam.copyWith(userId: '1234')),
    );

    expect(error, 'Enter a valid 17-digit SteamID64.');
    expect(api.validatedCredentials, isEmpty);
  });

  test('ignores the user ID when online gallery imports are off', () async {
    final value = settings();

    final error = await SteamProvider(api: api).configurationError(
      value.copyWith(steam: value.steam.copyWith(userId: 'not-used')),
    );

    expect(error, isNull);
    expect(api.validatedCredentials, [('', validApiKey)]);
  });

  test('validates Steam authentication for local imports', () async {
    final value = settings();

    final error = await SteamProvider(api: api).configurationError(
      value.copyWith(steam: value.steam.copyWith(userId: '')),
    );

    expect(error, isNull);
    expect(api.validatedCredentials, [('', validApiKey)]);
  });

  test('uses a selected userdata candidate in automatic mode', () async {
    await addLocalScreenshot('10', 'local');
    api.names['10'] = 'Test Game';
    final value = settings();
    final automatic = value.copyWith(
      steam: value.steam.copyWith(
        useCustomPath: false,
        userdataPath: p.join(steam.path, 'userdata'),
      ),
    );

    final result = await SteamProvider(api: api).collect(automatic);

    expect(result.imported, 1);
  });

  test('uses custom names and ignores configured app IDs', () async {
    await addLocalScreenshot('10', 'ignored');
    await addLocalScreenshot('20', 'custom');

    final result = await SteamProvider(
      api: api,
    ).collect(settings(ignoredGames: [' 10 '], customGames: {'20': 'My/Game'}));

    expect(result.imported, 1);
    expect(Directory(p.join(output.path, 'PC', '10')).existsSync(), isFalse);
    expect(
      Directory(p.join(output.path, 'PC', 'My_Game')).existsSync(),
      isTrue,
    );
  });

  test('imports online screenshots and saves covers', () async {
    api.names['30'] = 'Online Game';
    api.published = [
      SteamPublishedScreenshot(
        appId: '30',
        fileUrl: 'https://example.test/image',
        createdAt: DateTime(2026, 7, 8, 9, 10, 11),
        shortcutName: '',
      ),
    ];
    api.downloads['https://example.test/image'] = [1, 2, 3];
    api.covers['30'] = [4, 5, 6];

    final result = await SteamProvider(api: api)
        .collect(settings(onlineGallery: true, downloadCovers: true));

    final album = p.join(output.path, 'PC', 'Online Game');
    expect(result.imported, 1);
    expect(File(p.join(album, '2026-07-08_09-10-11.jpg')).readAsBytesSync(), [
      1,
      2,
      3,
    ]);
    expect(File(p.join(album, 'cover.jpg')).readAsBytesSync(), [4, 5, 6]);
  });

  test('moves an existing album to its custom game name', () async {
    api.names['40'] = 'Original Game';
    final original = Directory(p.join(output.path, 'PC', 'Original Game'));
    await original.create(recursive: true);
    await File(p.join(original.path, '2026-01-02_03-04-05.jpg'))
        .writeAsString('screenshot');
    await File(p.join(original.path, 'cover.jpg')).writeAsString('cover');

    await SteamProvider(api: api)
        .collect(settings(customGames: {'40': 'Custom Game'}));

    final renamed = Directory(p.join(output.path, 'PC', 'Custom Game'));
    expect(original.existsSync(), isFalse);
    expect(
      File(p.join(renamed.path, '2026-01-02_03-04-05.jpg')).readAsStringSync(),
      'screenshot',
    );
    expect(File(p.join(renamed.path, 'cover.jpg')).readAsStringSync(), 'cover');
  });

  test('merges a renamed album without losing screenshots', () async {
    api.names['50'] = 'Store Name';
    final original = Directory(p.join(output.path, 'PC', 'Store Name'));
    final custom = Directory(p.join(output.path, 'PC', 'Custom Name'));
    await original.create(recursive: true);
    await custom.create(recursive: true);
    await File(p.join(original.path, 'shared.jpg')).writeAsString('old');
    await File(p.join(original.path, 'unique.jpg')).writeAsString('unique');
    await File(p.join(original.path, 'cover.jpg')).writeAsString('old cover');
    await File(p.join(custom.path, 'shared.jpg')).writeAsString('new');
    await File(p.join(custom.path, 'cover.jpg')).writeAsString('new cover');

    await SteamProvider(api: api)
        .collect(settings(customGames: {'50': 'Custom Name'}));

    final files = custom
        .listSync()
        .whereType<File>()
        .map((file) => p.basename(file.path))
        .toList();
    expect(original.existsSync(), isFalse);
    expect(File(p.join(custom.path, 'shared.jpg')).readAsStringSync(), 'new');
    expect(
      File(p.join(custom.path, 'unique.jpg')).readAsStringSync(),
      'unique',
    );
    expect(
      File(p.join(custom.path, 'cover.jpg')).readAsStringSync(),
      'new cover',
    );
    expect(files.where((name) => name.startsWith('shared_')), hasLength(1));
  });
}

class _FakeSteamApi implements SteamApi {
  final names = <String, String>{};
  final ids = <String, String>{};
  final downloads = <String, List<int>>{};
  final covers = <String, List<int>>{};
  List<SteamPublishedScreenshot> published = const [];
  Exception? credentialFailure;
  final validatedCredentials = <(String, String)>[];

  @override
  Future<void> validateCredentials(String userId, String apiKey) async {
    validatedCredentials.add((userId, apiKey));
    final failure = credentialFailure;
    if (failure != null) {
      throw failure;
    }
  }

  @override
  Future<String?> appIdForName(String name, String apiKey) async => ids[name];

  @override
  Future<List<int>> download(String url) async => downloads[url]!;

  @override
  Future<List<int>?> gameCover(String appId) async => covers[appId];

  @override
  Future<String?> gameName(String appId, String apiKey) async => names[appId];

  @override
  Future<List<SteamPublishedScreenshot>> publishedScreenshots(
    String userId,
    String apiKey,
  ) async => published;
}
