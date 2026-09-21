import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/controllers/library_controller.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/models/library.dart';
import 'package:gaming_memories/providers/battle_net_provider.dart';
import 'package:gaming_memories/providers/guild_wars_2_provider.dart';
import 'package:gaming_memories/providers/playstation_4_provider.dart';
import 'package:gaming_memories/providers/screenshot_provider.dart';
import 'package:gaming_memories/providers/steam_provider.dart';
import 'package:gaming_memories/services/config_store.dart';
import 'package:gaming_memories/services/app_log.dart';
import 'package:gaming_memories/services/battle_net_games.dart';
import 'package:gaming_memories/services/folder_access_service.dart';
import 'package:gaming_memories/services/library_scanner.dart';
import 'package:gaming_memories/services/library_watcher.dart';
import 'package:gaming_memories/services/provider_paths.dart';
import 'package:gaming_memories/services/screenshot_action_service.dart';
import 'package:gaming_memories/services/steam_client.dart';
import 'package:gaming_memories/services/timeline_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  test('disables an invalid provider during startup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gaming-memories-controller-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );
    await store.save(
      const AppSettings(
        outputPath: '',
        playStation4: ProviderSettings(
          enabled: true,
          useCustomPath: true,
          sourcePath: '/definitely/missing/gaming-memories',
        ),
      ),
    );
    final controller = LibraryController(
      configStore: store,
      scanner: const LibraryScanner(),
      providers: const [PlayStation4Provider()],
    );

    await controller.initialize();

    expect(controller.settings.playStation4.enabled, isFalse);
    expect((await store.load()).playStation4.enabled, isFalse);
    expect(controller.notificationKind, NotificationKind.error);
    expect(
      controller.error,
      'PlayStation 4 was disabled: PlayStation 4 folder does not exist.',
    );
    expect(controller.providerValidationErrors, {
      'PlayStation 4': 'PlayStation 4 folder does not exist.',
    });
  });

  test('disables an invalid provider during a settings save', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gaming-memories-controller-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );
    final controller = LibraryController(
      configStore: store,
      scanner: const LibraryScanner(),
      providers: const [PlayStation4Provider()],
    )..isInitializing = false;

    final saved = await controller.updateSettings(
      const AppSettings(
        outputPath: '',
        playStation4: ProviderSettings(
          enabled: true,
          useCustomPath: true,
          sourcePath: '/definitely/missing/gaming-memories',
        ),
      ),
    );

    expect(saved, isTrue);
    expect(controller.settings.playStation4.enabled, isFalse);
    expect((await store.load()).playStation4.enabled, isFalse);
    expect(controller.notificationKind, NotificationKind.error);
    expect(
      controller.error,
      'PlayStation 4 was disabled: PlayStation 4 folder does not exist.',
    );
  });

  test(
    'disables Steam when its active online option lacks a user ID',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gaming-memories-controller-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final steamFolder = Directory(p.join(directory.path, 'steam'));
      await steamFolder.create();
      final store = ConfigStore(
        filePath: p.join(directory.path, 'settings.json'),
      );
      final controller = LibraryController(
        configStore: store,
        scanner: const LibraryScanner(),
        providers: [SteamProvider(api: const _ControllerSteamApi())],
      )..isInitializing = false;

      await controller.updateSettings(
        AppSettings(
          outputPath: '',
          steam: SteamSettings(
            enabled: true,
            useCustomPath: true,
            userdataPath: steamFolder.path,
            onlineGallery: true,
            userId: '',
            apiKey: '0123456789abcdef0123456789abcdef',
            downloadCovers: false,
            ignoredGames: const [],
            customGames: const {},
          ),
        ),
      );

      expect(controller.settings.steam.enabled, isFalse);
      expect((await store.load()).steam.enabled, isFalse);
      expect(controller.providerValidationErrors, {
        'Steam': 'Enter a Steam user ID for online gallery imports.',
      });
      expect(controller.notificationKind, NotificationKind.error);
      expect(
        controller.error,
        'Steam was disabled: Enter a Steam user ID for online gallery imports.',
      );
    },
  );

  test(
    'publishes the album tree before the timeline cache completes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gaming-memories-controller-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = ConfigStore(
        filePath: p.join(directory.path, 'settings.json'),
      );
      await store.save(AppSettings(outputPath: directory.path));
      final timelineCache = _BlockingLoadTimelineCache();
      final controller = LibraryController(
        configStore: store,
        scanner: _StartupFolderScanner(directory.path),
        timelineCache: timelineCache,
        providers: const [],
      );

      final initialization = controller.initialize();
      await timelineCache.started.future;
      for (
        var attempt = 0;
        attempt < 100 && controller.isAlbumTreeLoading;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(controller.isAlbumTreeLoading, isFalse);
      expect(controller.isInitializing, isTrue);
      expect(controller.folderTree.single.name, 'PC');

      timelineCache.result.complete(const []);
      await initialization;

      expect(controller.isInitializing, isFalse);
    },
  );

  test('shows game media before preview preparation completes', () async {
    final scanner = _ProgressiveFolderScanner();
    final controller =
        LibraryController(
            configStore: const ConfigStore(filePath: 'unused'),
            scanner: scanner,
            providers: const [],
          )
          ..isInitializing = false
          ..settings = const AppSettings(outputPath: '/library');

    controller.showAlbum('PC', 'Game');
    await scanner.prepareStarted.future;

    expect(controller.visibleMedia, [scanner.media]);
    expect(controller.isViewLoading, isTrue);

    scanner.prepareRelease.complete();
    for (
      var attempt = 0;
      attempt < 100 && controller.isViewLoading;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(controller.isViewLoading, isFalse);
  });

  test(
    'loads the timeline cache before its background scan completes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gaming-memories-controller-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = ConfigStore(
        filePath: p.join(directory.path, 'settings.json'),
      );
      await store.save(AppSettings(outputPath: directory.path));
      final cache = TimelineCache(
        filePath: p.join(directory.path, 'timeline-cache.json'),
      );
      final cached = MediaItem(
        path: p.join(directory.path, 'PC', 'Game', 'cached.jpg'),
        platform: 'PC',
        game: 'Game',
        capturedAt: DateTime(2026, 1, 1),
        kind: MediaKind.image,
      );
      await cache.save(directory.path, [cached]);
      final scanner = _BlockingScanner();
      final controller = LibraryController(
        configStore: store,
        scanner: scanner,
        timelineCache: cache,
        providers: const [],
      );

      await controller.initialize();

      expect(controller.isInitializing, isFalse);
      expect(controller.timelineMedia.single.path, cached.path);
      expect(controller.isTimelineRefreshing, isTrue);

      final refreshed = MediaItem(
        path: p.join(directory.path, 'PC', 'Game', 'refreshed.jpg'),
        platform: 'PC',
        game: 'Game',
        capturedAt: DateTime(2026, 2, 1),
        kind: MediaKind.image,
      );
      scanner.scanResult.complete(
        MediaLibrary(
          albums: [
            GameAlbum(platform: 'PC', game: 'Game', media: [refreshed]),
          ],
        ),
      );
      for (
        var attempt = 0;
        attempt < 100 && controller.isTimelineRefreshing;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(controller.isTimelineRefreshing, isFalse);
      expect(controller.timelineMedia.single.path, refreshed.path);
      expect((await cache.load(directory.path)).single.path, refreshed.path);
    },
  );

  test('applies watched media changes without another full scan', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gaming-memories-controller-',
    );
    final library = Directory(p.join(directory.path, 'library'));
    await Directory(p.join(library.path, 'PC', 'Game')).create(recursive: true);
    addTearDown(() => directory.delete(recursive: true));
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );
    await store.save(AppSettings(outputPath: library.path));
    final cache = TimelineCache(
      filePath: p.join(directory.path, 'timeline-cache.json'),
    );
    final scanner = _WatchScanner(library.path);
    final watcher = _FakeLibraryWatcher();
    final controller = LibraryController(
      configStore: store,
      scanner: scanner,
      timelineCache: cache,
      libraryWatcher: watcher,
      providers: const [],
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await _waitForController(
      () => !controller.isTimelineRefreshing && watcher.paths.isNotEmpty,
    );
    expect(scanner.scanCalls, 1);
    expect(watcher.paths.single, p.normalize(p.absolute(library.path)));
    controller.showAlbum('PC', 'Game');
    await _waitForController(() => !controller.isViewLoading);

    final media = MediaItem(
      path: p.join(library.path, 'PC', 'Game', 'new.jpg'),
      platform: 'PC',
      game: 'Game',
      capturedAt: DateTime(2026, 1, 2),
      kind: MediaKind.image,
      thumbnailPath: p.join(directory.path, 'new.thumb.jpg'),
      sourceModifiedAt: DateTime(2026, 1, 2),
      sourceSize: 123,
    );
    scanner.listing = FolderListing(folders: const [], media: [media]);
    watcher.add(
      LibraryChange(
        kind: LibraryChangeKind.create,
        path: media.path,
        isDirectory: false,
      ),
    );
    await _waitForController(() => controller.timelineMedia.isNotEmpty);
    await _waitForCache(cache, library.path, (items) => items.isNotEmpty);

    expect(controller.timelineMedia.single.path, media.path);
    expect(controller.visibleMedia.single.path, media.path);
    expect((await cache.load(library.path)).single.path, media.path);
    expect(scanner.scanCalls, 1);

    scanner.listing = const FolderListing.empty();
    watcher.add(
      LibraryChange(
        kind: LibraryChangeKind.delete,
        path: media.path,
        isDirectory: false,
      ),
    );
    await _waitForController(() => controller.timelineMedia.isEmpty);
    await _waitForCache(cache, library.path, (items) => items.isEmpty);

    expect(await cache.load(library.path), isEmpty);
    expect(controller.visibleMedia, isEmpty);
    expect(scanner.scanCalls, 1);

    final subAlbumPath = p.join(library.path, 'PC', 'Game', 'New album');
    final nested = MediaItem(
      path: p.join(subAlbumPath, 'nested.jpg'),
      platform: 'PC',
      game: 'Game',
      capturedAt: DateTime(2026, 1, 3),
      kind: MediaKind.image,
      subAlbumPath: 'New album',
      sourceModifiedAt: DateTime(2026, 1, 3),
      sourceSize: 456,
    );
    scanner.treeMedia = [nested];
    watcher.add(
      LibraryChange(
        kind: LibraryChangeKind.create,
        path: subAlbumPath,
        isDirectory: true,
      ),
    );
    await _waitForController(
      () => controller.timelineMedia.any((item) => item.path == nested.path),
    );
    expect(scanner.mediaTreeCalls, 1);
    expect(scanner.scanCalls, 1);

    await controller.collect();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(scanner.scanCalls, 1);

    await controller.refresh();
    await _waitForController(
      () => scanner.scanCalls == 2 && !controller.isTimelineRefreshing,
    );
    expect(scanner.scanCalls, 2);
  });

  test('refreshes the timeline when the folder watcher cannot start', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gaming-memories-controller-',
    );
    final library = Directory(p.join(directory.path, 'library'));
    await library.create();
    addTearDown(() => directory.delete(recursive: true));
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );
    await store.save(AppSettings(outputPath: library.path));
    final scanner = _WatchScanner(library.path);
    final controller = LibraryController(
      configStore: store,
      scanner: scanner,
      libraryWatcher: const _FailingLibraryWatcher(),
      providers: const [],
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await _waitForController(() => !controller.isTimelineRefreshing);

    expect(scanner.scanCalls, 1);
    expect(controller.error, isNull);
  });

  test('selects a platform and shows its games without media', () {
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [],
    );
    final older = MediaItem(
      path: '/pc-old.jpg',
      platform: 'PC',
      game: 'Diablo IV',
      capturedAt: DateTime(2026, 1, 1),
      kind: MediaKind.image,
    );
    final newer = MediaItem(
      path: '/pc-new.jpg',
      platform: 'PC',
      game: 'Minecraft',
      capturedAt: DateTime(2026, 2, 1),
      kind: MediaKind.image,
    );
    final console = MediaItem(
      path: '/console.jpg',
      platform: 'PlayStation 5',
      game: 'Astro Bot',
      capturedAt: DateTime(2026, 3, 1),
      kind: MediaKind.image,
    );
    controller.library = MediaLibrary(
      albums: [
        GameAlbum(platform: 'PC', game: 'Diablo IV', media: [older]),
        GameAlbum(platform: 'PC', game: 'Minecraft', media: [newer]),
        GameAlbum(
          platform: 'PlayStation 5',
          game: 'Astro Bot',
          media: [console],
        ),
      ],
    );

    controller.showPlatform('PC');

    expect(controller.view, LibraryView.platform);
    expect(controller.pageTitle, 'PC');
    expect(controller.selectedGame, isNull);
    expect(controller.visibleMedia, isEmpty);
    expect(controller.gameFolders.map((folder) => folder.name), [
      'Diablo IV',
      'Minecraft',
    ]);
  });

  test('loads sidebar sub-albums only after a game expands', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gaming-memories-controller-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final subAlbum = Directory(
      p.join(directory.path, 'PC', 'Game', 'Boss fights'),
    );
    await subAlbum.create(recursive: true);
    final controller =
        LibraryController(
            configStore: const ConfigStore(filePath: 'unused'),
            scanner: const LibraryScanner(),
            providers: const [],
          )
          ..isInitializing = false
          ..settings = AppSettings(outputPath: directory.path)
          ..folderTree = [
            LibraryFolder(
              name: 'PC',
              path: p.join(directory.path, 'PC'),
              children: [
                LibraryFolder(
                  name: 'Game',
                  path: p.join(directory.path, 'PC', 'Game'),
                  relativePath: 'Game',
                  childrenLoaded: false,
                ),
              ],
            ),
          ];

    expect(controller.folderTree.single.children.single.children, isEmpty);

    await controller.loadSubAlbums('PC', 'Game');

    final game = controller.folderTree.single.children.single;
    expect(game.childrenLoaded, isTrue);
    expect(game.children.single.name, 'Boss fights');
    expect(game.children.single.relativePath, 'Boss fights');
  });

  test('reports provider progress during collection', () async {
    final provider = _ProgressProvider();
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: [provider],
    );

    final collection = controller.collect();
    await Future<void>.delayed(Duration.zero);

    expect(controller.isBusy, isTrue);
    expect(controller.progressMessage, 'Importing test screenshots…');
    expect(controller.progressValue, 0.5);

    provider.release.complete();
    await collection;

    expect(controller.isBusy, isFalse);
    expect(controller.progressMessage, isNull);
    expect(controller.progressValue, isNull);
  });

  test(
    'warns and continues when automatic provider discovery finds nothing',
    () async {
      if (Platform.isWindows) {
        return;
      }

      final directory = await Directory.systemTemp.createTemp(
        'gaming-memories-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final controller =
          LibraryController(
              configStore: ConfigStore(
                filePath: p.join(directory.path, 'settings.json'),
              ),
              scanner: const LibraryScanner(),
              providers: const [
                // Pin the game folders at a home that holds nothing, so the
                // test does not see what is installed on the machine.
                BattleNetProvider(
                  locator: BattleNetLocator(
                    operatingSystem: 'linux',
                    allowEnvironmentHome: false,
                  ),
                ),
                GuildWars2Provider(),
              ],
            )
            ..settings = AppSettings(
              outputPath: directory.path,
              battleNet: const BattleNetSettings(enabled: true),
              guildWars2: const ProviderSettings(
                enabled: true,
                useCustomPath: false,
                sourcePath: '',
              ),
            );

      await controller.collect();

      expect(controller.error, isNull);
      expect(controller.notifications, hasLength(2));
      expect(
        controller.notifications.map((notification) => notification.message),
        [
          'Battle.net was skipped because none of its games were found. Turn on a game in Settings, or point it at a custom folder.',
          'Guild Wars 2 was skipped because no installation was found.',
        ],
      );
      expect(
        controller.notifications.map((notification) => notification.kind),
        everyElement(NotificationKind.warning),
      );
      expect(controller.notificationKind, NotificationKind.warning);
    },
  );

  test('returns from media details to the same library view', () {
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [],
    );
    final media = MediaItem(
      path: '/pc.jpg',
      platform: 'PC',
      game: 'Diablo IV',
      capturedAt: DateTime(2026, 1, 1),
      kind: MediaKind.image,
    );

    controller.showPlatform('PC');
    controller.showMedia(media);

    expect(controller.view, LibraryView.platform);
    expect(controller.selectedPlatform, 'PC');
    expect(controller.selectedMedia, same(media));

    controller.closeMedia();

    expect(controller.view, LibraryView.platform);
    expect(controller.selectedPlatform, 'PC');
    expect(controller.selectedMedia, isNull);
  });

  test('runs media file actions and reports success', () async {
    final actions = _FakeScreenshotActions();
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [],
      screenshotActions: actions,
    );
    final media = MediaItem(
      path: '/pc.jpg',
      platform: 'PC',
      game: 'Diablo IV',
      capturedAt: DateTime(2026, 1, 1),
      kind: MediaKind.image,
    );

    await controller.openMediaLocation(media);
    await controller.copyMediaImage(media);
    await controller.copyMediaPath(media);

    expect(actions.openedPaths, ['/pc.jpg']);
    expect(actions.copiedImages, ['/pc.jpg']);
    expect(actions.copiedPaths, ['/pc.jpg']);
    expect(controller.message, 'Path copied.');
    expect(controller.error, isNull);
  });

  test('selects a nested sub-album', () {
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [],
    );
    final video = MediaItem(
      path: '/PS5/Game/Other/clip.webm',
      platform: 'PlayStation 5',
      game: 'Game',
      subAlbumPath: 'Other',
      capturedAt: DateTime(2026, 1, 1),
      kind: MediaKind.video,
    );
    controller.library = MediaLibrary(
      albums: [
        GameAlbum(
          platform: 'PlayStation 5',
          game: 'Game',
          media: const [],
          subAlbums: [
            SubAlbum(name: 'Other', relativePath: 'Other', media: [video]),
          ],
        ),
      ],
    );

    controller.showSubAlbum('PlayStation 5', 'Game', 'Other');

    expect(controller.view, LibraryView.subAlbum);
    expect(controller.pageTitle, 'Other');
    expect(controller.visibleMedia, [video]);
  });

  test('restores library access before the first scan', () async {
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => directory.delete(recursive: true));
    final events = <String>[];
    final access = _FakeFolderAccess(events: events);
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );
    await store.save(
      AppSettings(
        outputPath: directory.path,
        folderGrants: {
          FolderGrantIds.library: FolderGrant(
            platform: 'macos',
            path: directory.path,
            access: FolderGrantAccess.readWrite,
            bookmark: 'library-bookmark',
          ),
        },
      ),
    );
    final controller = LibraryController(
      configStore: store,
      scanner: _RecordingScanner(events),
      providers: const [],
      folderAccess: access,
    );

    await controller.initialize();

    expect(events, ['activate:${directory.path}']);
    expect(controller.isInitializing, isFalse);
    for (var attempt = 0; attempt < 100 && events.length < 2; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(events, ['activate:${directory.path}', 'scan:${directory.path}']);
    expect(controller.libraryNeedsAuthorization, isFalse);
    expect(
      controller.folderAuthorization(FolderGrantIds.library).status,
      FolderAuthorizationStatus.ready,
    );
  });

  test('does not save an invalid folder selection', () async {
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );
    final initial = AppSettings(outputPath: directory.path);
    await store.save(initial);
    final missing = p.join(directory.path, 'missing');
    final access = _FakeFolderAccess(
      chosen: FolderAccessLease(
        grant: FolderGrant(
          platform: 'macos',
          path: missing,
          access: FolderGrantAccess.readWrite,
          bookmark: 'new-bookmark',
        ),
        token: 'new-lease',
      ),
    );
    final controller = LibraryController(
      configStore: store,
      scanner: const LibraryScanner(),
      providers: const [],
      folderAccess: access,
    )..settings = initial;

    final result = await controller.chooseFolder(SettingsFolderTarget.library);

    expect(result.saved, isFalse);
    expect(controller.settings.outputPath, directory.path);
    expect((await store.load()).outputPath, directory.path);
    expect(access.released, ['new-lease']);
  });

  test('warns separately for every provider missing folder access', () async {
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );
    await store.save(
      AppSettings(
        outputPath: directory.path,
        folderGrants: {
          FolderGrantIds.library: FolderGrant(
            platform: 'macos',
            path: directory.path,
            access: FolderGrantAccess.readWrite,
            bookmark: 'library-bookmark',
          ),
        },
      ),
    );
    final controller = LibraryController(
      configStore: store,
      scanner: const LibraryScanner(),
      providers: const [
        _FolderProvider('First', FolderGrantIds.battleNet),
        _FolderProvider('Second', FolderGrantIds.guildWars2),
      ],
      folderAccess: _FakeFolderAccess(),
    );
    await controller.initialize();

    await controller.collect();

    expect(controller.error, isNull);
    expect(
      controller.notifications.map((notification) => notification.message),
      [
        'First was skipped because its screenshot folders need access. Open Settings and allow access.',
        'Second was skipped because its screenshot folders need access. Open Settings and allow access.',
      ],
    );
    expect(
      controller.notifications.map((notification) => notification.kind),
      everyElement(NotificationKind.warning),
    );
  });

  test('releases provider access when collection fails', () async {
    final log = _RecordingAppLog();
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    final source = Directory(p.join(directory.path, 'source'))..createSync();
    addTearDown(() => directory.delete(recursive: true));
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );
    await store.save(
      AppSettings(
        outputPath: directory.path,
        folderGrants: {
          FolderGrantIds.library: FolderGrant(
            platform: 'macos',
            path: directory.path,
            access: FolderGrantAccess.readWrite,
            bookmark: 'library-bookmark',
          ),
          FolderGrantIds.battleNet: FolderGrant(
            platform: 'macos',
            path: source.path,
            access: FolderGrantAccess.readOnly,
            bookmark: 'source-bookmark',
          ),
        },
      ),
    );
    final access = _FakeFolderAccess();
    final controller = LibraryController(
      configStore: store,
      scanner: const LibraryScanner(),
      providers: [_ThrowingFolderProvider(source.path)],
      folderAccess: access,
      log: log,
    );
    await controller.initialize();

    await controller.collect();

    expect(
      access.released.where((token) => token == 'lease:${source.path}'),
      hasLength(2),
    );
    expect(controller.notifications.single.kind, NotificationKind.warning);
    expect(
      log.entries.join('\n'),
      allOf(
        contains('Provider "Throwing" failed'),
        contains('Bad state: provider failed'),
        contains('_ThrowingFolderProvider.collect'),
      ),
    );
    // The user reads a sentence, not the exception.
    expect(
      controller.notifications.single.message,
      isNot(contains('Bad state')),
    );
  });

  test('redacts the Steam API key from provider failure diagnostics', () async {
    const apiKey = 'super-secret-api-key';
    final log = _RecordingAppLog();
    final controller =
        LibraryController(
            configStore: const ConfigStore(filePath: 'unused'),
            scanner: const LibraryScanner(),
            providers: const [_ThrowingProvider(apiKey)],
            log: log,
          )
          ..settings = const AppSettings.defaults().copyWith(
            steam: const SteamSettings.disabled().copyWith(apiKey: apiKey),
          );

    await controller.collect();

    final output = log.entries.join('\n');
    expect(output, contains('Provider "Steam" failed'));
    expect(output, contains('key=<REDACTED>'));
    expect(output, isNot(contains(apiKey)));
    expect(controller.notifications.single.message, isNot(contains(apiKey)));
  });

  test('points the macOS chooser at the selected automatic folder', () async {
    final access = _FakeFolderAccess();
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [],
      folderAccess: access,
      providerPaths: const _TestProviderPathResolver([
        '/Steam One/userdata',
        '/Steam Two/userdata',
      ]),
    );

    final result = await controller.chooseFolder(
      SettingsFolderTarget.steamAutomatic,
      initialPath: '/Steam Two/userdata',
    );

    expect(result.cancelled, isTrue);
    expect(access.requests, hasLength(1));
    expect(access.requests.single.initialPath, '/Steam Two/userdata');
    expect(access.requests.single.suggestedPath, '/Steam Two/userdata');
    expect(access.requests.single.message, contains('Click Allow Access'));
  });

  test('points the macOS chooser at a Battle.net game folder', () async {
    final access = _FakeFolderAccess();
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [
        BattleNetProvider(
          locator: BattleNetLocator(
            operatingSystem: 'macos',
            userHomeDirectory: '/home/tester',
            allowEnvironmentHome: false,
          ),
        ),
      ],
      folderAccess: access,
      providerPaths: const _TestProviderPathResolver([]),
    );

    final result = await controller.chooseFolder(
      SettingsFolderTarget.battleNetGameAutomatic,
      gameId: 'wow_retail',
    );

    expect(result.cancelled, isTrue);
    expect(
      access.requests.single.id,
      BattleNetProvider.grantIdForGame('wow_retail'),
    );
    expect(
      access.requests.single.suggestedPath,
      '/Applications/World of Warcraft/_retail_/Screenshots',
    );
  });

  test('a Battle.net folder choice needs a game', () async {
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [BattleNetProvider()],
      folderAccess: _FakeFolderAccess(),
      providerPaths: const _TestProviderPathResolver([]),
    );

    final result = await controller.chooseFolder(
      SettingsFolderTarget.battleNetGameAutomatic,
    );

    expect(result.saved, isFalse);
  });

  test('saves PlayStation folder access as a custom provider path', () async {
    final directory = await Directory.systemTemp.createTemp('gaming-memories-');
    final captures = Directory(p.join(directory.path, 'PS5 captures'))
      ..createSync();
    addTearDown(() => directory.delete(recursive: true));
    final access = _FakeFolderAccess(
      chosen: FolderAccessLease(
        grant: FolderGrant(
          platform: 'macos',
          path: captures.path,
          access: FolderGrantAccess.readOnly,
          bookmark: 'playstation-bookmark',
        ),
        token: 'playstation-lease',
      ),
    );
    final store = ConfigStore(
      filePath: p.join(directory.path, 'settings.json'),
    );
    final controller = LibraryController(
      configStore: store,
      scanner: const LibraryScanner(),
      providers: const [],
      folderAccess: access,
    );

    final result = await controller.chooseFolder(
      SettingsFolderTarget.playStation5Custom,
    );

    expect(result.saved, isTrue);
    expect(controller.settings.playStation5.enabled, isTrue);
    expect(controller.settings.playStation5.useCustomPath, isTrue);
    expect(controller.settings.playStation5.sourcePath, captures.path);
    expect(
      controller.settings.folderGrants[FolderGrantIds.playStation5]?.bookmark,
      'playstation-bookmark',
    );
    expect((await store.load()).playStation5.sourcePath, captures.path);
  });

  test(
    'saves Nintendo Switch 2 folder access as a copied album path',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gaming-memories-',
      );
      final album = Directory(p.join(directory.path, 'Switch 2 album'))
        ..createSync();
      addTearDown(() => directory.delete(recursive: true));
      final access = _FakeFolderAccess(
        chosen: FolderAccessLease(
          grant: FolderGrant(
            platform: 'macos',
            path: album.path,
            access: FolderGrantAccess.readOnly,
            bookmark: 'switch-bookmark',
          ),
          token: 'switch-lease',
        ),
      );
      final store = ConfigStore(
        filePath: p.join(directory.path, 'settings.json'),
      );
      final controller = LibraryController(
        configStore: store,
        scanner: const LibraryScanner(),
        providers: const [],
        folderAccess: access,
      );

      final result = await controller.chooseFolder(
        SettingsFolderTarget.nintendoSwitch2Custom,
      );

      expect(result.saved, isTrue);
      expect(controller.settings.nintendoSwitch2.enabled, isTrue);
      expect(controller.settings.nintendoSwitch2.useCustomPath, isTrue);
      expect(controller.settings.nintendoSwitch2.sourcePath, album.path);
      expect(
        controller
            .settings
            .folderGrants[FolderGrantIds.nintendoSwitch2]
            ?.bookmark,
        'switch-bookmark',
      );
      expect((await store.load()).nintendoSwitch2.sourcePath, album.path);
    },
  );

  test(
    'saves automatic Hytale folder access without making it custom',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gaming-memories-',
      );
      final hytale = Directory(p.join(directory.path, 'Hytale Screenshots'))
        ..createSync();
      addTearDown(() => directory.delete(recursive: true));
      final access = _FakeFolderAccess(
        chosen: FolderAccessLease(
          grant: FolderGrant(
            platform: 'macos',
            path: hytale.path,
            access: FolderGrantAccess.readOnly,
            bookmark: 'hytale-bookmark',
          ),
          token: 'hytale-lease',
        ),
      );
      final store = ConfigStore(
        filePath: p.join(directory.path, 'settings.json'),
      );
      final controller = LibraryController(
        configStore: store,
        scanner: const LibraryScanner(),
        providers: const [],
        folderAccess: access,
        providerPaths: _TestProviderPathResolver(
          const [],
          hytalePath: hytale.path,
        ),
      );

      final result = await controller.chooseFolder(
        SettingsFolderTarget.hytaleAutomatic,
      );

      expect(result.saved, isTrue);
      expect(controller.settings.hytale.enabled, isTrue);
      expect(controller.settings.hytale.useCustomPath, isFalse);
      expect(controller.settings.hytale.sourcePath, hytale.path);
      expect(
        controller.settings.folderGrants[FolderGrantIds.hytale]?.bookmark,
        'hytale-bookmark',
      );
      expect((await store.load()).hytale.sourcePath, hytale.path);
    },
  );

  test(
    'saves automatic Minecraft folder access without making it custom',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gaming-memories-',
      );
      final minecraft = Directory(p.join(directory.path, 'screenshots'))
        ..createSync();
      addTearDown(() => directory.delete(recursive: true));
      final access = _FakeFolderAccess(
        chosen: FolderAccessLease(
          grant: FolderGrant(
            platform: 'macos',
            path: minecraft.path,
            access: FolderGrantAccess.readOnly,
            bookmark: 'minecraft-bookmark',
          ),
          token: 'minecraft-lease',
        ),
      );
      final store = ConfigStore(
        filePath: p.join(directory.path, 'settings.json'),
      );
      final controller = LibraryController(
        configStore: store,
        scanner: const LibraryScanner(),
        providers: const [],
        folderAccess: access,
        providerPaths: _TestProviderPathResolver(
          const [],
          minecraftPaths: [minecraft.path],
        ),
      );

      final result = await controller.chooseFolder(
        SettingsFolderTarget.minecraftAutomatic,
      );

      expect(result.saved, isTrue);
      expect(controller.settings.minecraft.enabled, isTrue);
      expect(controller.settings.minecraft.useCustomPath, isFalse);
      expect(controller.settings.minecraft.sourcePath, minecraft.path);
      expect(
        controller.settings.folderGrants[FolderGrantIds.minecraft]?.bookmark,
        'minecraft-bookmark',
      );
      expect((await store.load()).minecraft.sourcePath, minecraft.path);
    },
  );
}

class _FakeScreenshotActions implements ScreenshotActionService {
  final openedPaths = <String>[];
  final copiedImages = <String>[];
  final copiedPaths = <String>[];

  @override
  String get openLocationLabel => 'Open in file manager';

  @override
  Future<void> openLocation(String path) async => openedPaths.add(path);

  @override
  Future<void> copyImage(String path) async => copiedImages.add(path);

  @override
  Future<void> copyPath(String path) async => copiedPaths.add(path);
}

class _ProgressProvider implements ScreenshotProvider {
  final release = Completer<void>();

  @override
  String get name => 'Test';

  @override
  bool isEnabled(AppSettings settings) => true;

  @override
  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  }) async {
    onProgress?.call(
      const ProviderProgress(
        message: 'Importing test screenshots…',
        completed: 1,
        total: 2,
      ),
    );
    await release.future;
    return const ImportResult(provider: 'Test', imported: 1, skipped: 0);
  }
}

Future<void> _waitForController(bool Function() condition) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('The expected controller state did not arrive.');
}

Future<void> _waitForCache(
  TimelineCache cache,
  String libraryPath,
  bool Function(List<MediaItem>) condition,
) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (condition(await cache.load(libraryPath))) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('The expected timeline cache state did not arrive.');
}

class _FakeLibraryWatcher implements LibraryWatcher {
  final controller = StreamController<LibraryChange>.broadcast(sync: true);
  final List<String> paths = [];

  @override
  Future<Stream<LibraryChange>> watch(String rootPath) async {
    paths.add(rootPath);
    return controller.stream;
  }

  void add(LibraryChange change) => controller.add(change);
}

class _FailingLibraryWatcher implements LibraryWatcher {
  const _FailingLibraryWatcher();

  @override
  Future<Stream<LibraryChange>> watch(String rootPath) {
    throw const FileSystemException('Watcher unavailable.');
  }
}

class _WatchScanner extends LibraryScanner {
  _WatchScanner(this.root);

  final String root;
  int scanCalls = 0;
  int mediaTreeCalls = 0;
  FolderListing listing = const FolderListing.empty();
  List<MediaItem> treeMedia = const [];

  @override
  Future<MediaLibrary> scan(String outputPath) async {
    scanCalls++;
    return const MediaLibrary.empty();
  }

  @override
  Future<List<LibraryFolder>> folderTree(String outputPath) async {
    return [
      LibraryFolder(
        name: 'PC',
        path: p.join(root, 'PC'),
        children: [
          LibraryFolder(
            name: 'Game',
            path: p.join(root, 'PC', 'Game'),
            relativePath: 'Game',
            childrenLoaded: false,
          ),
        ],
      ),
    ];
  }

  @override
  Future<FolderListing> folderContents(
    String outputPath,
    String platform,
    String game, {
    String subAlbumPath = '',
    FolderListingCallback? onUpdate,
  }) async => listing;

  @override
  Future<MediaItem?> prepareMediaItem(MediaItem item) async => item;

  @override
  Future<List<MediaItem>> mediaTree(
    String outputPath,
    String platform,
    String game, {
    String subAlbumPath = '',
  }) async {
    mediaTreeCalls++;
    return treeMedia;
  }
}

class _RecordingScanner extends LibraryScanner {
  _RecordingScanner(this.events);

  final List<String> events;

  @override
  Future<MediaLibrary> scan(String outputPath) async {
    events.add('scan:$outputPath');
    return const MediaLibrary.empty();
  }
}

class _BlockingScanner extends LibraryScanner {
  final scanResult = Completer<MediaLibrary>();

  @override
  Future<List<LibraryFolder>> folderTree(String outputPath) async {
    return [LibraryFolder(name: 'PC', path: p.join(outputPath, 'PC'))];
  }

  @override
  Future<MediaLibrary> scan(String outputPath) => scanResult.future;
}

class _StartupFolderScanner extends LibraryScanner {
  _StartupFolderScanner(this.outputPath);

  final String outputPath;

  @override
  Future<List<LibraryFolder>> folderTree(String path) async {
    return [LibraryFolder(name: 'PC', path: p.join(outputPath, 'PC'))];
  }

  @override
  Future<MediaLibrary> scan(String outputPath) async {
    return const MediaLibrary.empty();
  }
}

class _BlockingLoadTimelineCache extends TimelineCache {
  _BlockingLoadTimelineCache() : super.disabled();

  final started = Completer<void>();
  final result = Completer<List<MediaItem>>();

  @override
  Future<List<MediaItem>> load(String libraryPath) {
    started.complete();
    return result.future;
  }
}

class _ProgressiveFolderScanner extends LibraryScanner {
  final prepareStarted = Completer<void>();
  final prepareRelease = Completer<void>();
  final media = MediaItem(
    path: '/library/PC/Game/2026-01-01_00-00-00.jpg',
    platform: 'PC',
    game: 'Game',
    capturedAt: DateTime(2026, 1, 1),
    kind: MediaKind.image,
  );

  @override
  Future<FolderListing> folderContents(
    String outputPath,
    String platform,
    String game, {
    String subAlbumPath = '',
    FolderListingCallback? onUpdate,
  }) async {
    final listing = FolderListing(folders: const [], media: [media]);
    onUpdate?.call(listing);
    return listing;
  }

  @override
  Future<FolderListing> prepareFolderContents(
    FolderListing listing, {
    FolderListingCallback? onUpdate,
    bool Function()? isCancelled,
  }) async {
    prepareStarted.complete();
    await prepareRelease.future;
    onUpdate?.call(listing);
    return listing;
  }
}

class _FakeFolderAccess implements FolderAccessService {
  _FakeFolderAccess({this.events, this.chosen});

  final List<String>? events;
  final FolderAccessLease? chosen;
  final List<String> released = [];
  final List<FolderAccessRequest> requests = [];

  @override
  bool get requiresPersistentGrant => true;

  @override
  Future<FolderAccessLease?> choose(FolderAccessRequest request) async {
    requests.add(request);
    return chosen;
  }

  @override
  Future<FolderAccessLease> activate(FolderGrant grant) async {
    events?.add('activate:${grant.path}');
    return FolderAccessLease(grant: grant, token: 'lease:${grant.path}');
  }

  @override
  Future<void> release(FolderAccessLease lease) async {
    released.add(lease.token);
  }

  @override
  Future<void> dispose() async {}
}

class _TestProviderPathResolver extends ProviderPathResolver {
  const _TestProviderPathResolver(
    this.paths, {
    this.hytalePath,
    this.minecraftPaths = const [],
  });

  final List<String> paths;
  final String? hytalePath;
  final List<String> minecraftPaths;

  @override
  String? hytaleScreenshots() => hytalePath;

  @override
  List<String> minecraftScreenshots() => minecraftPaths;

  @override
  List<String> steamUserdataCandidates() => paths;
}

/// Captures what would have gone to the log file, already redacted.
class _RecordingAppLog implements AppLog {
  final List<String> entries = [];

  @override
  String Function(String value)? redact;

  void _record(
    LogLevel level,
    String message,
    String? category,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final entry = [
      level.name,
      if (category != null) '[$category]',
      message,
      if (error != null) '$error',
      if (stackTrace != null) '$stackTrace',
    ].join(' ');
    entries.add(redact?.call(entry) ?? entry);
  }

  @override
  void debug(String message, {String? category}) =>
      _record(LogLevel.debug, message, category, null, null);

  @override
  void info(String message, {String? category}) =>
      _record(LogLevel.info, message, category, null, null);

  @override
  void warning(
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  }) => _record(LogLevel.warning, message, category, error, stackTrace);

  @override
  void error(
    String message, {
    String? category,
    Object? error,
    StackTrace? stackTrace,
  }) => _record(LogLevel.error, message, category, error, stackTrace);

  @override
  Future<String> read() async => entries.join('\n');

  @override
  Future<void> flush() async {}
}

class _ControllerSteamApi implements SteamApi {
  const _ControllerSteamApi();

  @override
  Future<void> validateCredentials(String userId, String apiKey) async {}

  @override
  Future<String?> appIdForName(String name, String apiKey) async => null;

  @override
  Future<List<int>> download(String url) async => const [];

  @override
  Future<List<int>?> gameCover(String appId) async => null;

  @override
  Future<String?> gameName(String appId, String apiKey) async => null;

  @override
  Future<List<SteamPublishedScreenshot>> publishedScreenshots(
    String userId,
    String apiKey,
  ) async => const [];
}

class _FolderProvider
    with SingleFolderRequirement
    implements FolderBackedScreenshotProvider {
  const _FolderProvider(this.name, this.folderGrantId);

  @override
  final String name;

  @override
  final String folderGrantId;

  @override
  bool isEnabled(AppSettings settings) => true;

  @override
  ProviderFolderRequirement? folderRequirement(AppSettings settings) {
    return ProviderFolderRequirement(
      id: folderGrantId,
      path: '/provider/$name',
      automatic: false,
    );
  }

  @override
  AppSettings withFolderPath(AppSettings settings, String path) => settings;

  @override
  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  }) async => ImportResult.empty(name);
}

class _ThrowingFolderProvider
    with SingleFolderRequirement
    implements FolderBackedScreenshotProvider {
  const _ThrowingFolderProvider(this.path);

  final String path;

  @override
  String get name => 'Throwing';

  @override
  String get folderGrantId => FolderGrantIds.battleNet;

  @override
  bool isEnabled(AppSettings settings) => true;

  @override
  ProviderFolderRequirement? folderRequirement(AppSettings settings) {
    return ProviderFolderRequirement(
      id: folderGrantId,
      path: path,
      automatic: false,
    );
  }

  @override
  AppSettings withFolderPath(AppSettings settings, String path) => settings;

  @override
  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  }) {
    throw StateError('provider failed');
  }
}

class _ThrowingProvider implements ScreenshotProvider {
  const _ThrowingProvider(this.apiKey);

  final String apiKey;

  @override
  String get name => 'Steam';

  @override
  bool isEnabled(AppSettings settings) => true;

  @override
  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  }) {
    throw StateError('request failed: https://example.invalid/?key=$apiKey');
  }
}
