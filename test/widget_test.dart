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
import 'package:gaming_memories/providers/screenshot_provider.dart';
import 'package:gaming_memories/services/config_store.dart';
import 'package:gaming_memories/services/folder_access_service.dart';
import 'package:gaming_memories/services/library_scanner.dart';
import 'package:gaming_memories/services/provider_paths.dart';
import 'package:gaming_memories/services/screenshot_action_service.dart';
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
            providers: const [],
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
            providers: const [],
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
      providers: const [],
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

    expect(find.text('Media library'), findsOneWidget);
    expect(find.text('Color mode'), findsOneWidget);
    expect(find.text('Battle.net'), findsOneWidget);
    expect(find.text('Guild Wars 2'), findsOneWidget);
    expect(find.text('Nintendo Switch 2'), findsOneWidget);
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
      providers: const [],
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
      providers: const [],
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

  testWidgets('shows collection progress with a percentage', (tester) async {
    final controller =
        LibraryController(
            configStore: const ConfigStore(filePath: 'unused'),
            scanner: const LibraryScanner(),
            providers: const [],
          )
          ..isInitializing = false
          ..isBusy = true
          ..progressMessage = 'Importing Steam screenshots…'
          ..progressValue = 0.25;

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    expect(find.text('Importing Steam screenshots…'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    final toast = find.byKey(const ValueKey('progress-toast'));
    expect(toast, findsOneWidget);
    final toastRect = tester.getRect(toast);
    expect(toastRect.center.dx, greaterThan(400));
    expect(toastRect.center.dy, greaterThan(300));

    await tester.pumpWidget(const SizedBox.shrink());
  });

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
      providers: const [],
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

  testWidgets('shows each provider warning as an amber timed toast', (
    tester,
  ) async {
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [
        _WarningProvider('First provider'),
        _WarningProvider('Second provider'),
      ],
    )..isInitializing = false;

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    await controller.collect();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    const firstWarning = 'First provider was skipped because it was not found.';
    const secondWarning =
        'Second provider was skipped because it was not found.';
    final firstToast = find.byKey(const ValueKey('notification-toast-1'));
    final secondToast = find.byKey(const ValueKey('notification-toast-2'));
    expect(firstToast, findsOneWidget);
    expect(secondToast, findsOneWidget);
    expect(find.text(firstWarning), findsOneWidget);
    expect(find.text(secondWarning), findsOneWidget);
    expect(find.byIcon(FLucideIcons.alertTriangle), findsNWidgets(2));
    expect(tester.widget<FToast>(firstToast).variant, FToastVariant.primary);
    expect(tester.widget<FToast>(secondToast).variant, FToastVariant.primary);
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
      ),
    );
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [],
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
      find.byKey(
        const ValueKey('breadcrumb-media-/library/PC/Game/screenshot-12.jpg'),
      ),
      findsOneWidget,
    );
    expect(find.text('Image details'), findsOneWidget);
    expect(find.text('screenshot-12.jpg'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('media-open-location')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-copy-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-copy-path')), findsOneWidget);
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

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
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
      providers: const [],
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
      providers: const [],
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
      providers: const [],
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
            providers: const [],
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

  testWidgets('edits Steam ignored and custom game lists', (tester) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            providers: const [],
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
    final help = find.byKey(const ValueKey('steam-credentials-help'));
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();

    expect(find.text('Steam credentials'), findsOneWidget);
    expect(find.text('Steam user ID'), findsWidgets);
    expect(find.text('Steam Web API key'), findsWidgets);
    expect(find.text('https://steamcommunity.com/dev/apikey'), findsOneWidget);

    final closeHelp = find.byKey(
      const ValueKey('steam-credentials-help-close'),
    );
    await tester.ensureVisible(closeHelp);
    await tester.pumpAndSettle();
    await tester.tap(closeHelp);
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

    expect(controller.settings.steam.customGames, {
      '40': 'New Game',
      '50': 'Another Game',
    });
    expect(store.saved?.steam.customGames, {
      '40': 'New Game',
      '50': 'Another Game',
    });
    expect(find.text('Save settings'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-autosave-note')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('shows custom folders and only autosaves valid paths', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('gaming-memories-');
    final validSource = Directory(p.join(directory.path, 'diablo'))
      ..createSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            providers: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            battleNet: ProviderSettings(
              enabled: true,
              useCustomPath: false,
              sourcePath: '',
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('battle-net-path-field')), findsNothing);

    final customPath = find.byKey(const ValueKey('battle-net-custom-path'));
    await tester.ensureVisible(customPath);
    await tester.pumpAndSettle();
    await tester.tap(customPath);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('battle-net-path-field'));
    expect(field, findsOneWidget);
    expect(find.text('Choose a folder.'), findsOneWidget);
    expect(controller.settings.battleNet.useCustomPath, isFalse);

    await tester.enterText(field, validSource.path);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose a folder.'), findsNothing);
    expect(controller.settings.battleNet.useCustomPath, isTrue);
    expect(controller.settings.battleNet.sourcePath, validSource.path);
    expect(store.saved?.battleNet.sourcePath, validSource.path);

    final invalidPath = p.join(directory.path, 'missing');
    await tester.enterText(field, invalidPath);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Battle.net folder does not exist.'), findsOneWidget);
    expect(controller.settings.battleNet.sourcePath, validSource.path);
    expect(store.saved?.battleNet.sourcePath, validSource.path);

    await tester.tap(customPath);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('battle-net-path-field')), findsNothing);
    expect(controller.settings.battleNet.useCustomPath, isFalse);

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
            providers: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            battleNet: ProviderSettings(
              enabled: true,
              useCustomPath: true,
              sourcePath: '/definitely/missing/gaming-memories',
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Battle.net folder does not exist.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('shows and autosaves Hytale provider settings', (tester) async {
    final directory = Directory.systemTemp.createTempSync('gaming-memories-');
    final source = Directory(p.join(directory.path, 'Hytale Screenshots'))
      ..createSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            providers: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = AppSettings(
            outputPath: '',
            hytale: ProviderSettings(
              enabled: true,
              useCustomPath: true,
              sourcePath: source.path,
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();

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

  testWidgets('shows and autosaves Minecraft provider settings', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('gaming-memories-');
    final source = Directory(p.join(directory.path, 'minecraft-screenshots'))
      ..createSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            providers: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = AppSettings(
            outputPath: '',
            minecraft: ProviderSettings(
              enabled: true,
              useCustomPath: true,
              sourcePath: source.path,
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();

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

  testWidgets('edits Nintendo Switch 2 ignored album folders', (tester) async {
    final store = _MemoryConfigStore();
    final controller =
        LibraryController(
            configStore: store,
            scanner: const LibraryScanner(),
            providers: const [],
          )
          ..isInitializing = false
          ..view = LibraryView.settings
          ..settings = const AppSettings(
            outputPath: '',
            nintendoSwitch2: NintendoSwitch2Settings(
              enabled: true,
              useCustomPath: false,
              sourcePath: '',
              ignoredFolders: ['Otra carpeta'],
            ),
          );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pumpAndSettle();

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
            providers: const [],
            folderAccess: const _PersistentFolderAccess(),
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
            providers: const [],
            folderAccess: access,
            providerPaths: const _WidgetProviderPathResolver([
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

class _MemoryConfigStore extends ConfigStore {
  _MemoryConfigStore() : super(filePath: 'unused');

  AppSettings? saved;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
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

class _WarningProvider implements ScreenshotProvider {
  const _WarningProvider(this.name);

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
  const _PersistentFolderAccess();

  @override
  bool get requiresPersistentGrant => true;

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

class _WidgetProviderPathResolver extends ProviderPathResolver {
  const _WidgetProviderPathResolver(this.paths);

  final List<String> paths;

  @override
  List<String> steamUserdataCandidates() => paths;
}
