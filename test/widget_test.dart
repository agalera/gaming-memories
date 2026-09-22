import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:gaming_memories/app.dart';
import 'package:gaming_memories/controllers/library_controller.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/models/library.dart';
import 'package:gaming_memories/services/battle_net_games.dart';
import 'package:gaming_memories/services/config_store.dart';
import 'package:gaming_memories/services/folder_access_service.dart';
import 'package:gaming_memories/services/library_scanner.dart';
import 'package:gaming_memories/services/publish/publish_service.dart';
import 'package:gaming_memories/services/screenshot_action_service.dart';
import 'package:gaming_memories/services/source_paths.dart';
import 'package:gaming_memories/sources/battle_net_source.dart';
import 'package:gaming_memories/sources/playstation_4_source.dart';
import 'package:gaming_memories/sources/screenshot_source.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path/path.dart' as p;

void main() {
  testWidgets('shows progress while the startup album tree loads', (
    tester,
  ) async {
    final controller =
        LibraryController(
            configStore: const ConfigStore(filePath: 'unused'),
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..isAlbumTreeLoading = true;

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('albums-loading-spinner')),
      findsOneWidget,
    );
    expect(find.text('Your albums will appear here.'), findsNothing);

    controller.folderTree = const [LibraryFolder(name: 'PC', path: '/PC')];
    controller.isAlbumTreeLoading = false;
    controller.notifyListeners();
    await tester.pump();

    expect(find.byKey(const ValueKey('albums-loading-spinner')), findsNothing);
    expect(find.byKey(const ValueKey('platform-PC')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('loads game sub-albums after the game expands', (tester) async {
    final scanner = _LazySubAlbumScanner();
    final controller =
        LibraryController(
            configStore: const ConfigStore(filePath: 'unused'),
            scanner: scanner,
            sources: const [],
          )
          ..isInitializing = false
          ..settings = const AppSettings(outputPath: '/library')
          ..folderTree = const [
            LibraryFolder(
              name: 'PC',
              path: '/library/PC',
              children: [
                LibraryFolder(
                  name: 'Game',
                  path: '/library/PC/Game',
                  relativePath: 'Game',
                  childrenLoaded: false,
                ),
              ],
            ),
          ];

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('platform-toggle-PC')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('game-PC-Game-toggle')));
    await tester.pumpAndSettle();

    expect(scanner.calls, 1);
    expect(
      find.byKey(const ValueKey('sub-album-PC-Game-Boss fights-label')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows the timeline and opens settings', (tester) async {
    final directory = Directory.systemTemp.createTempSync('gaming-memories-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final controller = LibraryController(
      configStore: ConfigStore(
        filePath: p.join(directory.path, 'settings.json'),
      ),
      scanner: const LibraryScanner(),
      sources: const [],
    );
    await tester.runAsync(controller.initialize);

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Timeline'), findsWidgets);
    expect(find.text('Choose your library folder'), findsOneWidget);
    expect(tester.widget<FSidebar>(find.byType(FSidebar)).header, isNull);
    expect(find.text('Gaming Memories'), findsNothing);
    expect(find.text('LIBRARY'), findsNothing);
    expect(find.text('ALBUMS'), findsNothing);
    expect(find.byType(FSidebarGroup), findsOneWidget);
    final sidebarFinder = find.byKey(const ValueKey('library-sidebar'));
    final sidebar = tester.widget<FSidebar>(sidebarFinder);
    final sidebarStyle = sidebar.style(
      FTheme.of(tester.element(sidebarFinder)).sidebarStyle,
    );
    expect(sidebarStyle.contentPadding, const EdgeInsets.only(top: 8));
    expect(sidebarStyle.groupStyle.childrenPadding, EdgeInsets.zero);
    expect(sidebarStyle.footerPadding, EdgeInsets.zero);
    expect(tester.getSize(sidebarFinder).width, 256);

    await tester.drag(
      find.byKey(const ValueKey('sidebar-resize-handle')),
      const Offset(48, 0),
    );
    await tester.pump();
    expect(tester.getSize(sidebarFinder).width, 304);

    for (final key in [
      'refresh-sidebar-button',
      'scan-sidebar-button',
      'settings-sidebar-button',
    ]) {
      expect(
        tester.widget<FButton>(find.byKey(ValueKey(key))).variant,
        FButtonVariant.outline,
      );
    }
    expect(find.byType(FDivider), findsNothing);
    final footer = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('sidebar-footer')),
    );
    final footerBorder = (footer.decoration as BoxDecoration).border! as Border;
    expect(footerBorder.top.style, BorderStyle.solid);
    expect(footerBorder.top.width, greaterThan(0));
    expect(
      tester
          .widget<Padding>(find.byKey(const ValueKey('sidebar-footer-padding')))
          .padding,
      const EdgeInsets.fromLTRB(16, 12, 16, 12),
    );

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Media library'), findsNothing);
    expect(find.text('Color mode'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-tabs')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-tab-appearance')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-tab-library')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-tab-sources')), findsOneWidget);
    expect(find.text('Battle.net'), findsNothing);
    expect(find.byKey(const ValueKey('battle-net-custom-path')), findsNothing);

    await _openSettingsTab(tester, 'library');
    expect(find.text('Media library'), findsOneWidget);
    expect(find.text('Color mode'), findsNothing);

    await _openSettingsTab(tester, 'sources');
    expect(find.text('Battle.net'), findsOneWidget);
    expect(find.text('Guild Wars 2'), findsOneWidget);
    expect(find.text('Nintendo Switch'), findsOneWidget);
    expect(find.text('Nintendo Switch 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('battle-net-custom-path')), findsNothing);
    final sourceNames = [
      'Battle.net',
      'Guild Wars 2',
      'Hytale',
      'Minecraft',
      'Nintendo Switch',
      'Nintendo Switch 2',
      'PlayStation 4',
      'PlayStation 5',
      'Steam',
    ];
    final sourceOffsets = sourceNames
        .map((name) => tester.getTopLeft(find.text(name)).dy)
        .toList(growable: false);
    expect(sourceOffsets, orderedEquals([...sourceOffsets]..sort()));

    await _openSettingsTab(tester, 'battle-net');

    expect(find.text('Media library'), findsNothing);
    expect(find.byKey(const ValueKey('battle-net-summary')), findsOneWidget);
    for (final entry in {
      'hytale': 'hytale-enabled',
      'playstation-4': 'playstation-4-enabled',
      'playstation-5': 'playstation-5-enabled',
      'nintendo-switch': 'nintendo-switch-enabled',
      'nintendo-switch-2': 'nintendo-switch-2-enabled',
      'minecraft': 'minecraft-enabled',
      'guild-wars-2': 'guild-wars-2-enabled',
      'steam': 'steam-api-key-help',
    }.entries) {
      await _openSettingsTab(tester, entry.key);
      expect(find.byKey(ValueKey(entry.value)), findsOneWidget);
    }
    expect(
      tester
          .widget<FButton>(
            find.byKey(const ValueKey('settings-sidebar-button')),
          )
          .selected,
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selects a platform from the album tree', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final directory = Directory.systemTemp.createTempSync('gaming-memories-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final controller = LibraryController(
      configStore: ConfigStore(
        filePath: p.join(directory.path, 'settings.json'),
      ),
      scanner: const LibraryScanner(),
      sources: const [],
    );
    await tester.runAsync(controller.initialize);
    final cover = File(p.join(directory.path, 'cover.png'));
    cover.writeAsBytesSync(
      image_lib.encodePng(image_lib.Image(width: 400, height: 200)),
    );
    controller.library = MediaLibrary(
      albums: [
        GameAlbum(
          platform: 'PC',
          game: 'Diablo IV',
          media: [
            MediaItem(
              path: p.join(directory.path, 'missing.jpg'),
              thumbnailPath: p.join(directory.path, 'missing.jpg.thumb.jpg'),
              platform: 'PC',
              game: 'Diablo IV',
              capturedAt: DateTime(2026, 1, 1),
              kind: MediaKind.image,
            ),
          ],
          subAlbums: const [
            SubAlbum(
              name: 'Boss fights',
              relativePath: 'Boss fights',
              media: [],
            ),
          ],
        ),
      ],
    );
    controller.folderTree = [
      LibraryFolder(
        name: 'PC',
        path: 'PC',
        children: [
          LibraryFolder(
            name: 'Diablo IV',
            path: 'PC/Diablo IV',
            relativePath: 'Diablo IV',
            coverPath: cover.path,
            children: const [
              LibraryFolder(
                name: 'Boss fights',
                path: 'PC/Diablo IV/Boss fights',
                relativePath: 'Boss fights',
              ),
            ],
          ),
          const LibraryFolder(
            name: 'Game Two',
            path: 'PC/Game Two',
            relativePath: 'Game Two',
          ),
          const LibraryFolder(
            name: 'Game Three',
            path: 'PC/Game Three',
            relativePath: 'Game Three',
          ),
        ],
      ),
    ];

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    final galleryImage = tester.widget<Image>(find.byType(Image).first);
    expect(
      (galleryImage.image as FileImage).file.path,
      p.join(directory.path, 'missing.jpg.thumb.jpg'),
    );

    await tester.tap(find.text('PC'));
    await tester.pumpAndSettle();

    expect(controller.view, LibraryView.platform);
    expect(controller.pageTitle, 'PC');
    expect(controller.visibleMedia, isEmpty);
    expect(
      find.byKey(const ValueKey('game-card-PC/Diablo IV')),
      findsOneWidget,
    );
    final gameCards = [
      find.byKey(const ValueKey('game-card-PC/Diablo IV')),
      find.byKey(const ValueKey('game-card-PC/Game Two')),
      find.byKey(const ValueKey('game-card-PC/Game Three')),
    ];
    final firstCardTop = tester.getTopLeft(gameCards.first).dy;
    for (final card in gameCards.skip(1)) {
      expect(tester.getTopLeft(card).dy, firstCardTop);
    }
    final scrollRight = tester
        .getTopRight(find.byKey(const ValueKey('media-scroll-view')))
        .dx;
    final lastCardRight = tester.getTopRight(gameCards.last).dx;
    expect(scrollRight - lastCardRight, closeTo(24, 0.1));
    final coverFinder = find.byKey(const ValueKey('game-cover-PC/Diablo IV'));
    expect(tester.widget<Image>(coverFinder).fit, BoxFit.contain);
    expect(find.byType(SliverGrid), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('game-card-PC/Diablo IV')))
          .height,
      isNot(closeTo(245, 0.1)),
    );
    expect(find.text('Diablo IV  1'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('platform-toggle-PC')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.view, LibraryView.platform);
    expect(find.text('Diablo IV'), findsWidgets);
    expect(find.text('Diablo IV  1'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('game-PC-Diablo IV-label')));
    await tester.pump();

    expect(controller.view, LibraryView.album);
    expect(controller.pageTitle, 'Diablo IV');
    expect(
      find.byKey(const ValueKey('folder-card-PC/Diablo IV/Boss fights')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('breadcrumb-game-Diablo IV')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('folder-card-PC/Diablo IV/Boss fights')),
    );
    await tester.pump();

    expect(controller.view, LibraryView.subAlbum);
    expect(
      find.byKey(const ValueKey('breadcrumb-folder-Boss fights')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('breadcrumb-game-Diablo IV')));
    await tester.pump();
    expect(controller.view, LibraryView.album);

    final mediaPath = p.join(directory.path, 'missing.jpg');
    await tester.tap(find.byKey(ValueKey('media-card-$mediaPath')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('breadcrumb-game-Diablo IV')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('breadcrumb-media-$mediaPath')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('breadcrumb-game-Diablo IV')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.selectedMedia, isNull);
    expect(controller.view, LibraryView.album);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('adds a game to the open games list as it arrives', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller =
        LibraryController(
            configStore: const ConfigStore(filePath: 'unused'),
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..settings = const AppSettings(outputPath: '/library')
          ..folderTree = const [
            LibraryFolder(
              name: 'PC',
              path: '/library/PC',
              children: [
                LibraryFolder(
                  name: 'Game',
                  path: '/library/PC/Game',
                  relativePath: 'Game',
                ),
              ],
            ),
          ];
    controller.showPlatform('PC');

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    const arriving = ValueKey('game-card-/library/PC/New Game');
    expect(
      find.byKey(const ValueKey('game-card-/library/PC/Game')),
      findsOneWidget,
    );
    expect(find.byKey(arriving), findsNothing);

    // What the watcher queue does when a game folder lands.
    controller
      ..folderTree = const [
        LibraryFolder(
          name: 'PC',
          path: '/library/PC',
          children: [
            LibraryFolder(
              name: 'Game',
              path: '/library/PC/Game',
              relativePath: 'Game',
            ),
            LibraryFolder(
              name: 'New Game',
              path: '/library/PC/New Game',
              relativePath: 'New Game',
            ),
          ],
        ),
      ]
      ..notifyListeners();
    await tester.pump();

    expect(find.byKey(arriving), findsOneWidget);
    expect(find.text('New Game'), findsWidgets);

    controller
      ..folderTree = const [LibraryFolder(name: 'PC', path: '/library/PC')]
      ..notifyListeners();
    await tester.pump();

    expect(find.byKey(arriving), findsNothing);
    expect(
      find.byKey(const ValueKey('game-card-/library/PC/Game')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selects a sub-album and marks its video', (tester) async {
    const path = '/library/PlayStation 5/Game/Other/clip.webm';
    final video = MediaItem(
      path: path,
      thumbnailPath: '$path.thumb.jpg',
      platform: 'PlayStation 5',
      game: 'Game',
      subAlbumPath: 'Other',
      capturedAt: DateTime(2026, 1, 1),
      kind: MediaKind.video,
      duration: Duration(seconds: 30),
    );
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      sources: const [],
    )..isInitializing = false;
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

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    expect(find.text('Game  1'), findsNothing);
    expect(find.text('Other  1'), findsNothing);
    expect(find.byKey(const ValueKey('video-indicator-$path')), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('platform-toggle-PlayStation 5')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const ValueKey('game-PlayStation 5-Game-label')),
      findsOneWidget,
    );
    expect(find.text('Game  1'), findsNothing);
    expect(find.text('Other  1'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('game-PlayStation 5-Game-toggle')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const ValueKey('sub-album-PlayStation 5-Game-Other-label')),
      findsOneWidget,
    );
    expect(find.text('Other  1'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('sub-album-PlayStation 5-Game-Other-label')),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.view, LibraryView.subAlbum);
    expect(controller.pageTitle, 'Other');
    expect(controller.visibleMedia, [video]);

    final card = find.byKey(const ValueKey('media-card-$path'));
    await tester.tapAt(tester.getCenter(card), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Copy image'), findsNothing);
    expect(find.text('Copy path'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('shows source progress in the sidebar scan toast', (
    tester,
  ) async {
    final controller =
        LibraryController(
            configStore: const ConfigStore(filePath: 'unused'),
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..isBusy = true
          ..progressMessage = 'Importing World of Warcraft screenshots…'
          ..progressValue = 0.25;

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    final scanToast = find.byKey(const ValueKey('scan-status-toast'));
    final scanProgress = find.byKey(const ValueKey('scan-status-progress'));
    final scanButton = find.byKey(const ValueKey('scan-sidebar-button'));
    expect(scanToast, findsOneWidget);
    expect(find.text('Scanning · 25%'), findsOneWidget);
    expect(
      find.text('Importing World of Warcraft screenshots…'),
      findsOneWidget,
    );
    expect(tester.widget<FDeterminateProgress>(scanProgress).value, 0.25);
    expect(tester.widget<FButton>(scanButton).onPress, isNull);
    expect(tester.getSize(scanButton).height, tester.getSize(scanToast).height);
    expect(
      tester
          .widget<FButton>(find.byKey(const ValueKey('refresh-sidebar-button')))
          .onPress,
      isNull,
    );

    controller
      ..isBusy = false
      ..isTimelineRefreshing = true
      ..progressMessage = 'Refreshing the timeline cache…'
      ..progressValue = null
      ..notifyListeners();
    await tester.pump();

    expect(scanProgress, findsNothing);
    expect(find.text('Scan for captures'), findsOneWidget);
    expect(find.text('Collect from enabled sources'), findsOneWidget);
    expect(find.text('Refreshing…'), findsOneWidget);
    expect(find.text('Refreshing the timeline cache…'), findsNothing);
    expect(
      tester.widget<FProgress>(
        find.byKey(const ValueKey('library-status-progress')),
      ),
      isNotNull,
    );
    expect(tester.widget<FButton>(scanButton).onPress, isNull);

    controller
      ..isTimelineRefreshing = false
      ..progressMessage = null
      ..timelineMedia = [
        MediaItem(
          path: '/library/PC/Game/screenshot.jpg',
          platform: 'PC',
          game: 'Game',
          capturedAt: DateTime(2026, 1, 1),
          kind: MediaKind.image,
        ),
      ]
      ..settings = const AppSettings(outputPath: '/library')
      ..notifyListeners();
    await tester.pump();

    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('1 capture'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-status-progress')), findsNothing);
    expect(scanProgress, findsNothing);
    expect(
      tester
          .widget<FButton>(find.byKey(const ValueKey('refresh-sidebar-button')))
          .onPress,
      isNotNull,
    );
    expect(tester.widget<FButton>(scanButton).onPress, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'blocks force refresh during watched updates and matches height',
    (tester) async {
      final controller = _LibraryActivityController(
        const LibraryActivity(
          kind: LibraryActivityKind.updating,
          title: 'Updating library…',
          detail: '1 change',
        ),
      );

      await tester.pumpWidget(GamingMemoriesApp(controller: controller));
      await tester.pump();

      final statusToast = find.byKey(const ValueKey('library-status-toast'));
      final refreshButton = find.byKey(
        const ValueKey('refresh-sidebar-button'),
      );
      expect(tester.widget<FButton>(refreshButton).onPress, isNull);
      expect(
        tester.getSize(refreshButton).height,
        tester.getSize(statusToast).height,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('shows action results as bottom-right toasts', (tester) async {
    final actions = _MemoryScreenshotActions();
    final media = MediaItem(
      path: '/library/PC/Game/screenshot.jpg',
      platform: 'PC',
      game: 'Game',
      capturedAt: DateTime(2026, 1, 1),
      kind: MediaKind.image,
    );
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      sources: const [],
      screenshotActions: actions,
    )..isInitializing = false;

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    await controller.copyMediaPath(media);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final success = find.byKey(const ValueKey('notification-toast-1'));
    expect(success, findsOneWidget);
    expect(find.text('Path copied.'), findsOneWidget);
    final successRect = tester.getRect(success);
    expect(successRect.center.dx, greaterThan(400));
    expect(successRect.center.dy, greaterThan(300));

    actions.failCopyPath = true;
    await controller.copyMediaPath(media);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final error = find.byKey(const ValueKey('notification-toast-2'));
    expect(error, findsOneWidget);
    expect(find.textContaining('Could not copy the path'), findsOneWidget);
    expect(tester.widget<FToast>(error).variant, FToastVariant.destructive);
    final close = find.byKey(const ValueKey('notification-toast-close-2'));
    expect(close, findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    expect(error, findsOneWidget);

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(error, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('shows each source warning as an amber timed toast', (
    tester,
  ) async {
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      sources: const [
        _WarningSource('First source'),
        _WarningSource('Second source'),
      ],
    )..isInitializing = false;

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    await controller.collect();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    const firstWarning = 'First source was skipped because it was not found.';
    const secondWarning = 'Second source was skipped because it was not found.';
    final firstToast = find.byKey(const ValueKey('notification-toast-1'));
    final secondToast = find.byKey(const ValueKey('notification-toast-2'));
    expect(firstToast, findsOneWidget);
    expect(secondToast, findsOneWidget);
    expect(find.text(firstWarning), findsOneWidget);
    expect(find.text(secondWarning), findsOneWidget);
    expect(
      find.descendant(
        of: firstToast,
        matching: find.byIcon(FLucideIcons.alertTriangle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: secondToast,
        matching: find.byIcon(FLucideIcons.alertTriangle),
      ),
      findsOneWidget,
    );
    expect(tester.widget<FToast>(firstToast).variant, FToastVariant.primary);
    expect(tester.widget<FToast>(secondToast).variant, FToastVariant.primary);
    expect(tester.getRect(firstToast).center.dx, greaterThan(400));
    expect(tester.getRect(secondToast).center.dx, greaterThan(400));
    final firstIcon = find.descendant(
      of: firstToast,
      matching: find.byIcon(FLucideIcons.alertTriangle),
    );
    expect(
      IconTheme.of(tester.element(firstIcon)).color,
      const Color(0xffb45309),
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text(firstWarning))).style.color,
      const Color(0xffb45309),
    );
    expect(
      find.byKey(const ValueKey('notification-toast-close-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('notification-toast-close-2')),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 6));
    expect(firstToast, findsNothing);
    expect(secondToast, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opens media and restores the gallery scroll offset', (
    tester,
  ) async {
    final actions = _MemoryScreenshotActions();
    final media = List.generate(
      20,
      (index) => MediaItem(
        path: '/library/PC/Game/screenshot-$index.jpg',
        thumbnailPath: '/library/PC/Game/screenshot-$index.jpg.thumb.jpg',
        platform: 'PC',
        game: 'Game',
        capturedAt: DateTime(2026, 1, 1).add(Duration(days: index)),
        kind: MediaKind.image,
        subAlbumPath: p.join('Chapter One', 'Boss fights'),
      ),
    );
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      sources: const [],
      screenshotActions: actions,
    )..isInitializing = false;
    controller.library = MediaLibrary(
      albums: [GameAlbum(platform: 'PC', game: 'Game', media: media)],
    );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    final galleryLayout = tester.widget<Padding>(
      find.byKey(const ValueKey('media-gallery-layout')),
    );
    expect(galleryLayout.padding, const EdgeInsets.fromLTRB(24, 10, 0, 0));
    final galleryContentPadding = tester.widget<SliverPadding>(
      find.byKey(const ValueKey('media-gallery-content-padding')),
    );
    expect(galleryContentPadding.padding, const EdgeInsets.only(right: 24));

    final target = find.byKey(
      const ValueKey('media-card-/library/PC/Game/screenshot-12.jpg'),
    );
    final galleryScroll = find.descendant(
      of: find.byKey(const ValueKey('media-scroll-view')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(target, 350, scrollable: galleryScroll);
    await tester.pump(const Duration(milliseconds: 200));
    final scrollState = tester.state<ScrollableState>(galleryScroll);
    final offset = scrollState.position.pixels;
    expect(offset, greaterThan(0));

    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.selectedMedia, same(media[12]));
    expect(find.byKey(const ValueKey('breadcrumb-library')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('breadcrumb-platform-PC')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('breadcrumb-game-Game')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('breadcrumb-folder-Chapter One')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('breadcrumb-folder-${p.join('Chapter One', 'Boss fights')}'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('breadcrumb-media-/library/PC/Game/screenshot-12.jpg'),
      ),
      findsOneWidget,
    );
    final lastFolderText = find.descendant(
      of: find.byKey(
        ValueKey('breadcrumb-folder-${p.join('Chapter One', 'Boss fights')}'),
      ),
      matching: find.text('Boss fights'),
    );
    expect(
      tester.widget<Text>(lastFolderText).style?.fontWeight,
      FontWeight.w700,
    );
    final mediaBreadcrumbText = find.descendant(
      of: find.byKey(
        const ValueKey('breadcrumb-media-/library/PC/Game/screenshot-12.jpg'),
      ),
      matching: find.text('screenshot-12.jpg'),
    );
    expect(
      tester.widget<Text>(mediaBreadcrumbText).style?.fontWeight,
      FontWeight.w400,
    );
    expect(find.text('Image details'), findsOneWidget);
    expect(find.text('screenshot-12.jpg'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('media-open-location')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-copy-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-copy-path')), findsOneWidget);
    final copyPathButton = tester.widget<FButton>(
      find.byKey(const ValueKey('media-copy-path')),
    );
    final copyPathContext = tester.element(
      find.byKey(const ValueKey('media-copy-path')),
    );
    final baseButtonStyle = copyPathContext.theme.buttonStyles
        .resolve({copyPathButton.variant, copyPathContext.platformVariant})
        .resolve({copyPathButton.size, copyPathContext.platformVariant});
    final copyPathDecoration = copyPathButton
        .style(baseButtonStyle)
        .decoration
        .resolve({});
    expect(copyPathDecoration, isA<BoxDecoration>());
    expect(
      (copyPathDecoration as BoxDecoration).borderRadius,
      copyPathContext.theme.style.borderRadius.md,
    );
    expect(copyPathDecoration.border, isNotNull);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('media-copy-path')),
        matching: find.byKey(const ValueKey('content-header')),
      ),
      findsOneWidget,
    );
    final detailImage = tester.widget<Image>(
      find.byKey(const ValueKey('media-detail-image')),
    );
    expect((detailImage.image as FileImage).file.path, media[12].path);
    expect(scrollState.mounted, isTrue);
    expect(scrollState.position.pixels, offset);

    await tester.tap(find.byKey(const ValueKey('media-copy-path')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(actions.copiedPaths, [media[12].path]);

    await tester.tap(find.byKey(const ValueKey('media-back-button')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.selectedMedia, isNull);
    expect(find.text('Image details'), findsNothing);
    expect(scrollState.mounted, isTrue);
    expect(scrollState.position.pixels, offset);

    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(
      find.byKey(
        ValueKey('breadcrumb-folder-${p.join('Chapter One', 'Boss fights')}'),
      ),
    );
    await tester.pump();

    expect(controller.view, LibraryView.subAlbum);
    expect(
      controller.selectedSubAlbumPath,
      p.join('Chapter One', 'Boss fights'),
    );
    expect(controller.selectedMedia, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('filters and sorts gallery media from the content header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final media = [
      MediaItem(
        path: '/library/PC/Game/old.jpg',
        platform: 'PC',
        game: 'Game',
        capturedAt: DateTime(2026, 1, 1),
        kind: MediaKind.image,
      ),
      MediaItem(
        path: '/library/PC/Game/middle.mp4',
        platform: 'PC',
        game: 'Game',
        capturedAt: DateTime(2026, 1, 2),
        kind: MediaKind.video,
      ),
      MediaItem(
        path: '/library/PC/Game/new.jpg',
        platform: 'PC',
        game: 'Game',
        capturedAt: DateTime(2026, 1, 3),
        kind: MediaKind.image,
      ),
    ];
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      sources: const [],
    )..isInitializing = false;
    controller.library = MediaLibrary(
      albums: [GameAlbum(platform: 'PC', game: 'Game', media: media)],
    );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    List<String> cardPaths() => find
        .byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> && key.value.startsWith('media-card-');
        })
        .evaluate()
        .map(
          (element) => ((element.widget.key! as ValueKey<String>).value)
              .substring('media-card-'.length),
        )
        .toList(growable: false);

    expect(find.text('All (3)'), findsOneWidget);
    expect(find.text('Descending'), findsOneWidget);
    expect(find.text('Media'), findsNothing);
    expect(cardPaths(), [media[2].path, media[1].path, media[0].path]);
    expect(
      tester.getCenter(find.byKey(const ValueKey('media-filter-control'))).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('breadcrumb-library'))).dy,
        1,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('media-filter-select')));
    await tester.pumpAndSettle();
    expect(find.text('All (3)'), findsWidgets);
    expect(find.text('Screenshots (2)'), findsOneWidget);
    expect(find.text('Clips (1)'), findsOneWidget);
    await tester.tap(find.text('Screenshots (2)').last);
    await tester.pumpAndSettle();
    expect(cardPaths(), [media[2].path, media[0].path]);

    await tester.tap(find.byKey(const ValueKey('media-sort-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ascending').last);
    await tester.pumpAndSettle();
    expect(cardPaths(), [media[0].path, media[2].path]);

    await tester.tap(find.byKey(const ValueKey('media-filter-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clips (1)').last);
    await tester.pumpAndSettle();
    expect(cardPaths(), [media[1].path]);

    tester.view.physicalSize = const Size(800, 700);
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('media-filter-control'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('breadcrumb-library'))).dy,
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('zooms the detail image with a double tap and resets it', (
    tester,
  ) async {
    final media = List.generate(
      2,
      (index) => MediaItem(
        path: '/library/PC/Game/screenshot-$index.jpg',
        platform: 'PC',
        game: 'Game',
        capturedAt: DateTime(2026, 1, 1).add(Duration(days: index)),
        kind: MediaKind.image,
      ),
    );
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      sources: const [],
    )..isInitializing = false;
    controller.library = MediaLibrary(
      albums: [GameAlbum(platform: 'PC', game: 'Game', media: media)],
    );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    controller.showMedia(media.first);
    await tester.pump(const Duration(milliseconds: 200));

    final viewer = find.byKey(const ValueKey('media-detail-viewer'));
    Matrix4 transformation() => tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!
        .value;

    Future<void> doubleTap() async {
      await tester.tap(viewer);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(viewer);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(transformation().getMaxScaleOnAxis(), 1);

    await doubleTap();
    expect(transformation().getMaxScaleOnAxis(), closeTo(2.5, 0.01));

    await doubleTap();
    expect(transformation().getMaxScaleOnAxis(), closeTo(1, 0.01));

    await doubleTap();
    expect(transformation().getMaxScaleOnAxis(), closeTo(2.5, 0.01));

    controller.showMedia(media.last);
    await tester.pump(const Duration(milliseconds: 200));

    expect(transformation(), Matrix4.identity());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('pans, pinches and modifier-zooms with trackpad gestures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final media = [
      MediaItem(
        path: '/library/PC/Game/screenshot-0.jpg',
        platform: 'PC',
        game: 'Game',
        capturedAt: DateTime(2026, 1, 1),
        kind: MediaKind.image,
      ),
    ];
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      sources: const [],
    )..isInitializing = false;
    controller.library = MediaLibrary(
      albums: [GameAlbum(platform: 'PC', game: 'Game', media: media)],
    );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    controller.showMedia(media.first);
    await tester.pump(const Duration(milliseconds: 200));

    final viewer = find.byKey(const ValueKey('media-detail-viewer'));
    Matrix4 transformation() => tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!
        .value;

    // Zoomed in, so there is room to pan.
    await tester.tap(viewer);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(viewer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final zoomed = transformation().clone();
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(viewer)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
    await tester.pump();

    expect(
      transformation().getMaxScaleOnAxis(),
      closeTo(zoomed.getMaxScaleOnAxis(), 0.001),
    );
    expect(
      transformation().getTranslation().y,
      lessThan(zoomed.getTranslation().y),
    );

    final panned = transformation().clone();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(
      transformation().getMaxScaleOnAxis(),
      greaterThan(panned.getMaxScaleOnAxis()),
    );

    final modifierZoomed = transformation().clone();
    final pinch = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
      pointer: 7,
    );
    await pinch.panZoomStart(tester.getCenter(viewer));
    await tester.pump();
    await pinch.panZoomUpdate(tester.getCenter(viewer), scale: 1.2);
    await tester.pump();
    await pinch.panZoomEnd();
    await tester.pump();

    expect(
      transformation().getMaxScaleOnAxis(),
      greaterThan(modifierZoomed.getMaxScaleOnAxis()),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('shows image actions in the gallery context menu', (
    tester,
  ) async {
    final actions = _MemoryScreenshotActions();
    final media = MediaItem(
      path: '/library/PC/Game/screenshot.jpg',
      thumbnailPath: '/library/PC/Game/screenshot.jpg.thumb.jpg',
      platform: 'PC',
      game: 'Game',
      capturedAt: DateTime(2026, 1, 1),
      kind: MediaKind.image,
    );
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      sources: const [],
      screenshotActions: actions,
    )..isInitializing = false;
    controller.library = MediaLibrary(
      albums: [
        GameAlbum(platform: 'PC', game: 'Game', media: [media]),
      ],
    );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    final card = find.byKey(
      const ValueKey('media-card-/library/PC/Game/screenshot.jpg'),
    );
    await tester.tapAt(tester.getCenter(card), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Open in file manager'), findsOneWidget);
    expect(find.text('Copy image'), findsOneWidget);
    expect(find.text('Copy path'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('media-menu-copy-image-/library/PC/Game/screenshot.jpg'),
      ),
    );
    await tester.pumpAndSettle();

    expect(actions.copiedImages, [media.path]);
    expect(controller.selectedMedia, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('changes between dark and light modes', (tester) async {
    final controller =
        LibraryController(
            configStore: _MemoryConfigStore(),
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            themeMode: AppThemeMode.dark,
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    expect(
      FTheme.of(tester.element(find.byType(FScaffold))).colors.brightness,
      Brightness.dark,
    );

    await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
    await tester.pumpAndSettle();

    expect(controller.settings.themeMode, AppThemeMode.light);
    expect(
      FTheme.of(tester.element(find.byType(FScaffold))).colors.brightness,
      Brightness.light,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    controller.previewTheme(AppThemeMode.system);
    await tester.pumpAndSettle();

    expect(
      FTheme.of(tester.element(find.byType(FScaffold))).colors.brightness,
      Brightness.dark,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('saves a non-text setting only when its value changes', (
    tester,
  ) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            themeMode: AppThemeMode.dark,
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('theme-mode-dark')));
    await tester.pumpAndSettle();
    expect(store.saveCalls, 0);

    await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
    await tester.pumpAndSettle();
    expect(store.saveCalls, 1);

    await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
    await tester.pumpAndSettle();
    expect(store.saveCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('debounces text settings and flushes them on blur', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('gaming-memories-');
    final first = Directory(p.join(directory.path, 'first'))..createSync();
    final second = Directory(p.join(directory.path, 'second'))..createSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = AppSettings(outputPath: first.path);

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'library');

    final field = find.byKey(const ValueKey('library-path-field'));
    await tester.enterText(field, first.path);
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.saveCalls, 0);

    await tester.enterText(field, second.path);
    await tester.pump(const Duration(milliseconds: 299));
    expect(store.saveCalls, 0);

    await _openSettingsTab(tester, 'appearance');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(store.saveCalls, 1);
    expect(store.saved?.outputPath, second.path);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));

    final debouncedStore = _MemoryConfigStore();
    final debouncedController =
        LibraryController(
            configStore: debouncedStore,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = AppSettings(outputPath: second.path);
    await tester.pumpWidget(GamingMemoriesApp(controller: debouncedController));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'library');
    await tester.enterText(field, first.path);
    await tester.pump(const Duration(milliseconds: 299));
    expect(debouncedStore.saveCalls, 0);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(debouncedStore.saveCalls, 1);
    expect(debouncedStore.saved?.outputPath, first.path);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('edits Steam ignored and custom game lists', (tester) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            steam: SteamSettings(
              enabled: true,
              useCustomPath: false,
              userdataPath: '',
              onlineGallery: false,
              userId: '',
              apiKey: '',
              downloadCovers: false,
              ignoredGames: ['10'],
              customGames: {'30': 'Old Game'},
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    await _openSettingsTab(tester, 'steam');
    final help = find.byKey(const ValueKey('steam-api-key-help'));
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();

    expect(find.text('Steam Web API key'), findsWidgets);
    expect(find.text('Why Gaming Memories needs it'), findsOneWidget);
    expect(find.text('https://steamcommunity.com/dev/apikey'), findsOneWidget);

    final closeHelp = find.byKey(const ValueKey('steam-api-key-help-close'));
    await tester.ensureVisible(closeHelp);
    await tester.pumpAndSettle();
    await tester.tap(closeHelp);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('steam-user-id')), findsNothing);

    final ignoredHelp = find.byKey(const ValueKey('steam-ignored-help'));
    await tester.ensureVisible(ignoredHelp);
    await tester.tap(ignoredHelp);
    await tester.pumpAndSettle();

    expect(find.text('Ignored apps'), findsWidgets);
    final closeIgnoredHelp = find.byKey(
      const ValueKey('steam-ignored-help-close'),
    );
    await tester.ensureVisible(closeIgnoredHelp);
    await tester.pumpAndSettle();
    await tester.tap(closeIgnoredHelp);
    await tester.pumpAndSettle();

    final customHelp = find.byKey(const ValueKey('steam-custom-help'));
    await tester.ensureVisible(customHelp);
    await tester.tap(customHelp);
    await tester.pumpAndSettle();

    expect(find.text('Custom apps'), findsWidgets);
    final closeCustomHelp = find.byKey(
      const ValueKey('steam-custom-help-close'),
    );
    await tester.ensureVisible(closeCustomHelp);
    await tester.pumpAndSettle();
    await tester.tap(closeCustomHelp);
    await tester.pumpAndSettle();

    final input = find.byKey(const ValueKey('steam-ignored-input'));
    final ignoredAdd = find.byKey(const ValueKey('steam-ignored-add'));
    await tester.ensureVisible(input);
    expect(
      tester.getBottomLeft(input).dy,
      closeTo(tester.getBottomLeft(ignoredAdd).dy, 0.1),
    );
    await tester.enterText(input, '20');
    await tester.tap(ignoredAdd);
    await tester.pump();

    expect(find.text('10'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('steam-ignored-remove-10')));
    await tester.pump();
    expect(find.text('10'), findsNothing);
    expect(find.text('20'), findsOneWidget);

    final customId = find.byKey(const ValueKey('steam-custom-id-input'));
    final customName = find.byKey(const ValueKey('steam-custom-name-input'));
    final customAdd = find.byKey(const ValueKey('steam-custom-add'));
    await tester.ensureVisible(customId);
    expect(
      tester.getBottomLeft(customName).dy,
      closeTo(tester.getBottomLeft(customAdd).dy, 0.1),
    );
    await tester.enterText(customId, '40');
    await tester.enterText(customName, 'New Game');
    await tester.tap(customAdd);
    await tester.pump();

    expect(find.text('Old Game'), findsOneWidget);
    expect(find.text('New Game'), findsOneWidget);

    await tester.enterText(customId, '50');
    await tester.enterText(customName, 'Another Game');
    await tester.tap(customAdd);
    await tester.pump();

    expect(find.text('Old Game'), findsOneWidget);
    expect(find.text('New Game'), findsOneWidget);
    expect(find.text('Another Game'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('steam-custom-remove-30')));
    await tester.pump();
    expect(find.text('Old Game'), findsNothing);
    expect(find.text('New Game'), findsOneWidget);
    expect(find.text('Another Game'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(controller.settings.steam.customGames, {
      '40': 'New Game',
      '50': 'Another Game',
    });
    expect(store.saved?.steam.customGames, {
      '40': 'New Game',
      '50': 'Another Game',
    });
    expect(find.text('Settings saved.'), findsWidgets);
    expect(find.text('Save settings'), findsNothing);
    expect(find.byKey(const ValueKey('settings-autosave-note')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('disables Steam when an active option lacks its user ID', (
    tester,
  ) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [_WidgetSteamSource()],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = AppSettings(
            outputPath: '',
            steam: SteamSettings(
              enabled: true,
              useCustomPath: false,
              userdataPath: '',
              onlineGallery: true,
              userId: '76561198000000000',
              apiKey: '0123456789abcdef0123456789abcdef',
              downloadCovers: false,
              ignoredGames: const [],
              customGames: const {},
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    await _openSettingsTab(tester, 'steam');

    final userId = find.byKey(const ValueKey('steam-user-id'));
    await tester.ensureVisible(userId);
    await tester.enterText(userId, '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: userId, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      isEmpty,
    );
    expect(store.saved, isNotNull);
    expect(controller.settings.steam.enabled, isFalse);
    expect(store.saved?.steam.enabled, isFalse);
    expect(
      tester.widget<FSwitch>(find.byKey(const ValueKey('steam-enabled'))).value,
      isFalse,
    );
    expect(
      find.text('Enter a Steam user ID for online gallery imports.'),
      findsWidgets,
    );
    expect(
      find.text(
        'Steam was disabled: Enter a Steam user ID for online gallery imports.',
      ),
      findsOneWidget,
    );
    final toast = find.byKey(
      ValueKey('notification-toast-${controller.notificationRevision}'),
    );
    expect(tester.widget<FToast>(toast).variant, FToastVariant.destructive);
    expect(
      find.byKey(
        ValueKey('notification-toast-close-${controller.notificationRevision}'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('shows a row per Battle.net game with its own folder', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('gaming-memories-');
    final validSource = Directory(p.join(directory.path, 'starcraft'))
      ..createSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [
              BattleNetSource(
                locator: BattleNetLocator(
                  operatingSystem: 'macos',
                  userHomeDirectory: '/gaming-memories-missing-home',
                  allowEnvironmentHome: false,
                ),
              ),
            ],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            battleNet: BattleNetSettings(enabled: true),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'battle-net');

    // Every supported game is listed, installed or not.
    for (final game in battleNetGames) {
      expect(
        find.byKey(ValueKey('battle-net-game-${game.id}')),
        findsOneWidget,
        reason: game.name,
      );
    }
    expect(find.text('World of Warcraft'), findsWidgets);
    expect(
      find.byKey(const ValueKey('battle-net-game-starcraft_ii-path')),
      findsNothing,
    );

    final customPath = find.byKey(
      const ValueKey('battle-net-game-starcraft_ii-custom'),
    );
    await tester.ensureVisible(customPath);
    await tester.pumpAndSettle();
    await tester.tap(customPath);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(
      const ValueKey('battle-net-game-starcraft_ii-path'),
    );
    expect(field, findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
    expect(find.text('Allow Access'), findsNothing);

    await tester.enterText(field, validSource.path);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    final saved = controller.settings.battleNet.game('starcraft_ii');
    expect(saved.useCustomPath, isTrue);
    expect(saved.sourcePath, validSource.path);
    // Only the game that was edited changes.
    expect(
      controller.settings.battleNet.game('diablo_iii').useCustomPath,
      isFalse,
    );
    expect(
      store.saved?.battleNet.game('starcraft_ii').sourcePath,
      validSource.path,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('switching a Battle.net game off keeps the others on', (
    tester,
  ) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [
              BattleNetSource(
                locator: BattleNetLocator(
                  operatingSystem: 'macos',
                  userHomeDirectory: '/gaming-memories-missing-home',
                  allowEnvironmentHome: false,
                ),
              ),
            ],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            battleNet: BattleNetSettings(enabled: true),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'battle-net');

    final toggle = find.byKey(
      const ValueKey('battle-net-game-wow_classic-enabled'),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    tester.widget<FSwitch>(toggle).onChange!(false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(controller.settings.battleNet.game('wow_classic').enabled, isFalse);
    expect(controller.settings.battleNet.game('wow_retail').enabled, isTrue);
    expect(
      store.saved?.battleNet.game('wow_classic').enabled,
      isFalse,
      reason: 'the change is persisted',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('validates a saved custom folder when settings opens', (
    tester,
  ) async {
    final controller =
        LibraryController(
            configStore: _MemoryConfigStore(),
            scanner: const LibraryScanner(),
            sources: const [
              BattleNetSource(
                locator: BattleNetLocator(
                  operatingSystem: 'macos',
                  userHomeDirectory: '/gaming-memories-missing-home',
                  allowEnvironmentHome: false,
                ),
              ),
            ],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            battleNet: BattleNetSettings(
              enabled: true,
              games: {
                'diablo_iii': SourceSettings(
                  enabled: true,
                  useCustomPath: true,
                  sourcePath: '/definitely/missing/gaming-memories',
                ),
              },
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'battle-net');

    expect(
      find.text('Diablo III screenshot folder does not exist.'),
      findsWidgets,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('disables an active source after an invalid folder edit', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('gaming-memories-');
    final validSource = Directory(p.join(directory.path, 'captures'))
      ..createSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [PlayStation4Source()],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = AppSettings(
            outputPath: '',
            playStation4: SourceSettings(
              enabled: true,
              useCustomPath: true,
              sourcePath: validSource.path,
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    await _openSettingsTab(tester, 'playstation-4');

    final field = find.byKey(const ValueKey('playstation-4-path-field'));
    await tester.enterText(field, p.join(directory.path, 'missing'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(controller.settings.playStation4.enabled, isFalse);
    expect(controller.settings.playStation4.sourcePath, validSource.path);
    expect(store.saved?.playStation4.enabled, isFalse);
    expect(
      tester
          .widget<FSwitch>(find.byKey(const ValueKey('playstation-4-enabled')))
          .value,
      isFalse,
    );
    expect(
      find.text('PlayStation 4 exported media folder does not exist.'),
      findsWidgets,
    );
    expect(
      find.text(
        'PlayStation 4 was disabled: PlayStation 4 exported media folder does not exist.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('keeps a source disabled when its folder is invalid', (
    tester,
  ) async {
    final controller =
        LibraryController(
            configStore: _MemoryConfigStore(),
            scanner: const LibraryScanner(),
            sources: const [
              BattleNetSource(
                locator: BattleNetLocator(
                  operatingSystem: 'macos',
                  userHomeDirectory: '/gaming-memories-missing-home',
                  allowEnvironmentHome: false,
                ),
              ),
            ],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            battleNet: BattleNetSettings(
              enabled: false,
              games: {
                'diablo_iii': SourceSettings(
                  enabled: true,
                  useCustomPath: true,
                  sourcePath: '/definitely/missing/gaming-memories',
                ),
              },
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'battle-net');

    final enabled = find.byKey(const ValueKey('battle-net-enabled'));
    expect(tester.widget<FSwitch>(enabled).value, isFalse);
    tester.widget<FSwitch>(enabled).onChange!(true);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<FSwitch>(enabled).value, isFalse);
    expect(controller.settings.battleNet.enabled, isFalse);
    expect(
      find.text('Diablo III screenshot folder does not exist.'),
      findsWidgets,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('shows and autosaves Hytale source settings', (tester) async {
    final directory = Directory.systemTemp.createTempSync('gaming-memories-');
    final source = Directory(p.join(directory.path, 'Hytale Screenshots'))
      ..createSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = AppSettings(
            outputPath: '',
            hytale: SourceSettings(
              enabled: true,
              useCustomPath: true,
              sourcePath: source.path,
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'hytale');

    expect(find.byKey(const ValueKey('hytale-path-field')), findsOneWidget);
    final cover = find.byKey(const ValueKey('hytale-bundled-cover'));
    await tester.ensureVisible(cover);
    await tester.tap(cover);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(controller.settings.hytale.downloadCovers, isTrue);
    expect(store.saved?.hytale.downloadCovers, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('shows and autosaves Minecraft source settings', (tester) async {
    final directory = Directory.systemTemp.createTempSync('gaming-memories-');
    final source = Directory(p.join(directory.path, 'minecraft-screenshots'))
      ..createSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = AppSettings(
            outputPath: '',
            minecraft: SourceSettings(
              enabled: true,
              useCustomPath: true,
              sourcePath: source.path,
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'minecraft');

    expect(find.byKey(const ValueKey('minecraft-path-field')), findsOneWidget);
    expect(find.text('PC · Launcher and Flatpak screenshots'), findsOneWidget);
    final enabled = find.byKey(const ValueKey('minecraft-enabled'));
    await tester.ensureVisible(enabled);
    tester.widget<FSwitch>(enabled).onChange!(false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<FSwitch>(enabled).value, isFalse);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(controller.settings.minecraft.enabled, isFalse);
    expect(store.saved?.minecraft.enabled, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('edits Nintendo Switch ignored album folders', (tester) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            nintendoSwitch: NintendoSwitchSettings(
              enabled: true,
              useCustomPath: false,
              sourcePath: '',
              ignoredFolders: ['Otra carpeta'],
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'nintendo-switch');

    final input = find.byKey(const ValueKey('nintendo-switch-ignored-input'));
    final add = find.byKey(const ValueKey('nintendo-switch-ignored-add'));
    await tester.ensureVisible(input);
    await tester.enterText(input, 'News');
    await tester.tap(add);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('nintendo-switch-ignored-remove-Otra carpeta')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(controller.settings.nintendoSwitch.ignoredFolders, ['News']);
    expect(store.saved?.nintendoSwitch.ignoredFolders, ['News']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('edits Nintendo Switch 2 ignored album folders', (tester) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            nintendoSwitch2: NintendoSwitchSettings(
              enabled: true,
              useCustomPath: false,
              sourcePath: '',
              ignoredFolders: ['Otra carpeta'],
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'nintendo-switch-2');

    final input = find.byKey(const ValueKey('nintendo-switch-2-ignored-input'));
    final add = find.byKey(const ValueKey('nintendo-switch-2-ignored-add'));
    await tester.ensureVisible(input);
    await tester.enterText(input, 'News');
    await tester.tap(add);
    await tester.pump();
    await tester.tap(
      find.byKey(
        const ValueKey('nintendo-switch-2-ignored-remove-Otra carpeta'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(controller.settings.nintendoSwitch2.ignoredFolders, ['News']);
    expect(store.saved?.nintendoSwitch2.ignoredFolders, ['News']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('shows missing macOS access immediately in settings', (
    tester,
  ) async {
    final controller =
        LibraryController(
            configStore: _MemoryConfigStore(),
            scanner: const LibraryScanner(),
            sources: const [],
            folderAccess: _PersistentFolderAccess(),
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(outputPath: '/saved/library');

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    await _openSettingsTab(tester, 'library');

    final field = tester.widget<FTextField>(
      find.byKey(const ValueKey('library-path-field')),
    );
    expect(field.readOnly, isTrue);
    expect(find.text('Allow access to the Library folder.'), findsOneWidget);
    expect(find.text('Allow Access'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('asks which automatic folder to authorize when several exist', (
    tester,
  ) async {
    final access = _RecordingPersistentFolderAccess();
    final controller =
        LibraryController(
            configStore: _MemoryConfigStore(),
            scanner: const LibraryScanner(),
            sources: const [],
            folderAccess: access,
            sourcePaths: const _WidgetSourcePathResolver([
              '/Steam One/userdata',
              '/Steam Two/userdata',
            ]),
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            steam: SteamSettings(
              enabled: true,
              useCustomPath: false,
              userdataPath: '',
              onlineGallery: false,
              userId: '',
              apiKey: '',
              downloadCovers: false,
              ignoredGames: [],
              customGames: {},
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'steam');

    final allow = find.byKey(const ValueKey('steam-automatic-folder-access'));
    await tester.ensureVisible(allow);
    await tester.tap(allow);
    await tester.pumpAndSettle();

    expect(find.text('Choose a Steam folder'), findsOneWidget);
    expect(
      find.textContaining('macOS will then ask you to confirm'),
      findsOneWidget,
    );
    expect(access.requests, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('automatic-folder-/Steam Two/userdata')),
    );
    await tester.pumpAndSettle();

    expect(access.requests, hasLength(1));
    expect(access.requests.single.suggestedPath, '/Steam Two/userdata');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('the publish tab hides its fields until publishing is on', (
    tester,
  ) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(outputPath: '');

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'publish');

    expect(find.byKey(const ValueKey('publish-enabled')), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-host')), findsNothing);

    final toggle = find.byKey(const ValueKey('publish-enabled'));
    await tester.ensureVisible(toggle);
    tester.widget<FSwitch>(toggle).onChange!(true);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('publish-site-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-host')), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-remote-path')), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-file-mode')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('publish-credential-automaticKey')),
      findsOneWidget,
    );
    // Automatic is the default, so no key has to be chosen.
    expect(find.byKey(const ValueKey('publish-key-path')), findsNothing);
    expect(
      find.byKey(const ValueKey('publish-transport-auto')),
      findsOneWidget,
    );

    expect(store.saved?.publish.enabled, isTrue);
  });

  testWidgets('the key field appears only for a chosen key file', (
    tester,
  ) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            publish: PublishSettings(enabled: true),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'publish');

    expect(find.byKey(const ValueKey('publish-key-path')), findsNothing);

    final manual = find.byKey(const ValueKey('publish-credential-manualKey'));
    await tester.ensureVisible(manual);
    await tester.tap(manual);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('publish-key-path')), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(
      store.saved?.publish.target.credential,
      PublishCredentialKind.manualKey,
    );

    final password = find.byKey(const ValueKey('publish-credential-password'));
    await tester.ensureVisible(password);
    await tester.tap(password);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('publish-key-path')), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(
      store.saved?.publish.target.credential,
      PublishCredentialKind.password,
    );
  });

  testWidgets('choosing a key asks for a chooser that can reach ~/.ssh', (
    tester,
  ) async {
    final home = Directory.systemTemp.createTempSync('gaming-memories-home-');
    Directory(p.join(home.path, '.ssh')).createSync();
    addTearDown(() => home.deleteSync(recursive: true));
    final keyPath = p.join(home.path, '.ssh', 'id_ed25519');
    final access = _RecordingFileChooser(answer: keyPath);
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
            folderAccess: access,
            sourcePaths: SourcePathResolver(userHomeDirectory: home.path),
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            publish: PublishSettings(
              enabled: true,
              target: PublishTargetSettings(
                host: 'example.com',
                port: 22,
                username: 'deploy',
                remotePath: '/srv/site',
                credential: PublishCredentialKind.manualKey,
                fileMode: '644',
                directoryMode: '755',
                deleteRemoved: true,
              ),
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'publish');

    final choose = find.widgetWithText(FButton, 'Choose');
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();

    expect(access.requests, hasLength(1));
    // file_picker cannot show hidden entries and, on macOS, refuses to open
    // at all without App Sandbox entitlements this app does not have.
    expect(access.requests.single.showHiddenFiles, isTrue);
    expect(access.requests.single.initialPath, p.join(home.path, '.ssh'));

    expect(
      tester
          .widget<FTextField>(find.byKey(const ValueKey('publish-key-path')))
          .control,
      isNotNull,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(store.saved?.publish.target.keyPath, keyPath);
  });

  testWidgets('a chooser that fails says so beside the field', (tester) async {
    final access = _RecordingFileChooser(
      failure: const FolderAccessException(
        'unavailable',
        'macOS could not open the file chooser.',
      ),
    );
    final controller =
        LibraryController(
            configStore: _MemoryConfigStore(),
            scanner: const LibraryScanner(),
            sources: const [],
            folderAccess: access,
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            publish: PublishSettings(
              enabled: true,
              target: PublishTargetSettings(
                host: 'example.com',
                port: 22,
                username: 'deploy',
                remotePath: '/srv/site',
                credential: PublishCredentialKind.manualKey,
                fileMode: '644',
                directoryMode: '755',
                deleteRemoved: true,
              ),
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'publish');

    final choose = find.widgetWithText(FButton, 'Choose');
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();

    expect(find.text('macOS could not open the file chooser.'), findsOneWidget);
  });
  testWidgets('excluding an album lists it and saves it', (tester) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            sources: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            publish: PublishSettings(enabled: true),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();
    await _openSettingsTab(tester, 'publish');

    expect(find.text('The whole library is published.'), findsOneWidget);

    final field = find.byKey(const ValueKey('publish-excluded-input'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Steam/Private');
    final add = find.byKey(const ValueKey('publish-excluded-add'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(find.text('Steam/Private'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(store.saved?.publish.excluded, ['Steam/Private']);

    final remove = find.byKey(
      const ValueKey('publish-excluded-remove-Steam/Private'),
    );
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(find.text('The whole library is published.'), findsOneWidget);
  });

  testWidgets('the sidebar Publish button follows the setting', (tester) async {
    final controller = _PublishingController()
      ..isInitializing = false
      ..settings = const AppSettings(outputPath: '/library');

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('publish-sidebar-button')), findsNothing);

    controller
      ..settings = _publishEnabledSettings
      ..notifyListeners();
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('publish-sidebar-button'));
    expect(button, findsOneWidget);
    expect(find.text('Publish'), findsWidgets);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(controller.publishCalls, 1);

    controller
      ..isPublishing = true
      ..publishProgressValue = 0.42
      ..publishProgressMessage = 'Uploading Steam/Hades/a.png (3/40)'
      ..notifyListeners();
    // Not pumpAndSettle: the progress bar animates and never settles.
    await tester.pump();

    // The button gives way to the toast while a publish runs.
    expect(find.byKey(const ValueKey('publish-sidebar-button')), findsNothing);
    expect(find.byKey(const ValueKey('publish-status-toast')), findsOneWidget);
    expect(find.text('Publishing · 42%'), findsOneWidget);
    expect(find.text('Uploading Steam/Hades/a.png (3/40)'), findsOneWidget);

    final progress = tester.widget<FDeterminateProgress>(
      find.byKey(const ValueKey('publish-status-progress')),
    );
    expect(progress.value, closeTo(0.42, 0.001));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the stop button stops the publish and then goes quiet', (
    tester,
  ) async {
    final controller = _PublishingController()
      ..isInitializing = false
      ..settings = _publishEnabledSettings
      ..isPublishing = true
      ..publishProgressValue = 0.1;

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    final stop = find.byKey(const ValueKey('publish-stop-button'));
    expect(stop, findsOneWidget);

    await tester.tap(stop);
    // The tappable animates on press, so its timer has to run out before the
    // test ends.
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.cancelCalls, 1);

    controller
      ..stopping = true
      ..notifyListeners();
    await tester.pump();

    // Asking twice does nothing, so the button stops offering it.
    expect(find.text('Stopping…'), findsOneWidget);
    expect(tester.widget<FButton>(stop).onPress, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a publish with no reported progress still shows movement', (
    tester,
  ) async {
    final controller = _PublishingController()
      ..isInitializing = false
      ..settings = _publishEnabledSettings
      ..isPublishing = true;

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('publish-status-progress')),
      findsOneWidget,
    );
    expect(
      tester.widget(find.byKey(const ValueKey('publish-status-progress'))),
      isA<FProgress>(),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _openSettingsTab(WidgetTester tester, String name) async {
  const directTabs = {'appearance', 'library', 'sources', 'publish'};
  final tabName = directTabs.contains(name) ? name : 'sources';
  final tab = find.byKey(ValueKey('settings-tab-$tabName'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
  if (!directTabs.contains(name)) {
    final card = find.byKey(ValueKey('source-card-$name'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
  }
}

class _LazySubAlbumScanner extends LibraryScanner {
  int calls = 0;

  @override
  Future<List<LibraryFolder>> subAlbumTree(
    String outputPath,
    String platform,
    String game,
  ) async {
    calls++;
    return const [
      LibraryFolder(
        name: 'Boss fights',
        path: '/library/PC/Game/Boss fights',
        relativePath: 'Boss fights',
      ),
    ];
  }
}

/// Counts publishes rather than running one, so the sidebar button can be
/// tested without a server.
class _PublishingController extends LibraryController {
  _PublishingController()
    : super(
        configStore: const ConfigStore(filePath: 'unused'),
        scanner: const LibraryScanner(),
        sources: const [],
        publishService: const _NoopPublishService(),
      );

  int publishCalls = 0;
  int cancelCalls = 0;

  /// Stands in for the cancellation the real publish owns, which a test
  /// driving the sidebar alone never creates.
  bool stopping = false;

  @override
  Future<void> publish({String? secret}) async => publishCalls++;

  @override
  Future<PublishSecretKind> publishSecretNeeded() async =>
      PublishSecretKind.none;

  @override
  void cancelPublish() {
    cancelCalls++;
    notifyListeners();
  }

  @override
  PublishActivity get publishActivity {
    final activity = super.publishActivity;
    if (!activity.isRunning || !stopping) {
      return activity;
    }
    return PublishActivity(
      isRunning: true,
      title: 'Stopping…',
      detail: 'Finishing the file in flight',
      progress: activity.progress,
      isStopping: true,
    );
  }
}

const _publishEnabledSettings = AppSettings(
  outputPath: '/library',
  publish: PublishSettings(
    enabled: true,
    target: PublishTargetSettings(
      host: 'example.com',
      port: 22,
      username: 'deploy',
      remotePath: '/srv/site',
      fileMode: '644',
      directoryMode: '755',
      deleteRemoved: true,
    ),
  ),
);

class _NoopPublishService extends PublishService {
  const _NoopPublishService() : super(buildPath: 'unused');
}

/// Records what the key chooser was asked for, and answers with a path.
class _RecordingFileChooser implements FolderAccessService {
  _RecordingFileChooser({this.answer, this.failure});

  final String? answer;
  final FolderAccessException? failure;
  final List<FileChoiceRequest> requests = [];

  @override
  bool get requiresPersistentGrant => false;

  @override
  Future<String?> chooseFile(FileChoiceRequest request) async {
    requests.add(request);
    final problem = failure;
    if (problem != null) {
      throw problem;
    }
    return answer;
  }

  @override
  Future<FolderAccessLease?> choose(FolderAccessRequest request) async => null;

  @override
  Future<FolderAccessLease> activate(FolderGrant grant) {
    throw UnimplementedError();
  }

  @override
  Future<void> release(FolderAccessLease lease) async {}

  @override
  Future<void> dispose() async {}
}

class _MemoryConfigStore extends ConfigStore {
  _MemoryConfigStore() : super(filePath: 'unused');

  AppSettings? saved;
  int saveCalls = 0;

  @override
  Future<void> save(AppSettings settings) async {
    saveCalls++;
    saved = settings;
  }
}

class _LibraryActivityController extends LibraryController {
  _LibraryActivityController(this.activity)
    : super(
        configStore: const ConfigStore(filePath: 'unused'),
        scanner: const LibraryScanner(),
        sources: const [],
      );

  final LibraryActivity activity;

  @override
  LibraryActivity get libraryActivity => activity;
}

class _WidgetSteamSource
    implements ScreenshotSource, SourceConfigurationValidator {
  const _WidgetSteamSource();

  @override
  String get name => 'Steam';

  @override
  bool isEnabled(AppSettings settings) => settings.steam.enabled;

  @override
  Future<String?> configurationError(AppSettings settings) async {
    if (settings.steam.onlineGallery && settings.steam.userId.trim().isEmpty) {
      return 'Enter a Steam user ID for online gallery imports.';
    }
    return null;
  }

  @override
  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  }) async => ImportResult.empty(name);
}

class _MemoryScreenshotActions implements ScreenshotActionService {
  final openedPaths = <String>[];
  final copiedImages = <String>[];
  final copiedPaths = <String>[];
  bool failCopyPath = false;

  @override
  String get openLocationLabel => 'Open in file manager';

  @override
  Future<void> openLocation(String path) async => openedPaths.add(path);

  @override
  Future<void> copyImage(String path) async => copiedImages.add(path);

  @override
  Future<void> copyPath(String path) async {
    if (failCopyPath) {
      throw StateError('copy failed');
    }
    copiedPaths.add(path);
  }
}

class _WarningSource implements ScreenshotSource {
  const _WarningSource(this.name);

  @override
  final String name;

  @override
  bool isEnabled(AppSettings settings) => true;

  @override
  Future<ImportResult> collect(
    AppSettings settings, {
    ProgressCallback? onProgress,
  }) async {
    return ImportResult.warning(
      name,
      '$name was skipped because it was not found.',
    );
  }
}

class _PersistentFolderAccess implements FolderAccessService {
  _PersistentFolderAccess();

  @override
  bool get requiresPersistentGrant => true;

  @override
  Future<String?> chooseFile(FileChoiceRequest request) async => null;

  @override
  Future<FolderAccessLease?> choose(FolderAccessRequest request) async => null;

  @override
  Future<FolderAccessLease> activate(FolderGrant grant) {
    throw UnimplementedError();
  }

  @override
  Future<void> release(FolderAccessLease lease) async {}

  @override
  Future<void> dispose() async {}
}

class _RecordingPersistentFolderAccess implements FolderAccessService {
  final List<FolderAccessRequest> requests = [];

  @override
  bool get requiresPersistentGrant => true;

  @override
  Future<String?> chooseFile(FileChoiceRequest request) async => chosenFilePath;

  String? chosenFilePath;

  @override
  Future<FolderAccessLease?> choose(FolderAccessRequest request) async {
    requests.add(request);
    return null;
  }

  @override
  Future<FolderAccessLease> activate(FolderGrant grant) {
    throw UnimplementedError();
  }

  @override
  Future<void> release(FolderAccessLease lease) async {}

  @override
  Future<void> dispose() async {}
}

class _WidgetSourcePathResolver extends SourcePathResolver {
  const _WidgetSourcePathResolver(this.paths);

  final List<String> paths;

  @override
  List<String> steamUserdataCandidates() => paths;
}
