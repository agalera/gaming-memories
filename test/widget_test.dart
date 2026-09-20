import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:gaming_memories/app.dart';
import 'package:gaming_memories/controllers/library_controller.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/models/library.dart';
import 'package:gaming_memories/services/config_store.dart';
import 'package:gaming_memories/services/library_scanner.dart';
import 'package:gaming_memories/services/screenshot_action_service.dart';
import 'package:path/path.dart' as p;

void main() {
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

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Media library'), findsOneWidget);
    expect(find.text('Color mode'), findsOneWidget);
    expect(find.text('Diablo IV'), findsOneWidget);
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
        ),
      ],
    );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    final galleryImage = tester.widget<Image>(find.byType(Image).first);
    expect(
      (galleryImage.image as FileImage).file.path,
      p.join(directory.path, 'missing.jpg.thumb.jpg'),
    );

    await tester.tap(find.text('PC'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(controller.view, LibraryView.platform);
    expect(controller.pageTitle, 'PC');
    expect(controller.visibleMedia, hasLength(1));
    expect(find.text('Diablo IV  1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('platform-toggle-PC')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.view, LibraryView.platform);
    expect(find.text('Diablo IV  1'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('platform-toggle-PC')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Diablo IV  1'));
    await tester.pump();

    expect(controller.view, LibraryView.album);
    expect(controller.pageTitle, 'Diablo IV');

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

    expect(find.text('Game  1'), findsOneWidget);
    expect(find.text('Other  1'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-indicator-$path')), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);

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

    final target = find.byKey(
      const ValueKey('media-card-/library/PC/Game/screenshot-12.jpg'),
    );
    final galleryScroll = find.descendant(
      of: find.byType(GridView),
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
    expect(find.text('Image details'), findsOneWidget);
    expect(find.text('screenshot-12.jpg'), findsOneWidget);
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
            diabloIV: ProviderSettings.disabled(),
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
            diabloIV: ProviderSettings.disabled(),
            steam: SteamSettings(
              enabled: true,
              userdataPath: 'auto',
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

    await tester.ensureVisible(find.text('Save settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save settings'));
    await tester.pump();

    expect(controller.settings.steam.customGames, {
      '40': 'New Game',
      '50': 'Another Game',
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });
}

class _MemoryConfigStore extends ConfigStore {
  _MemoryConfigStore() : super(filePath: 'unused');

  @override
  Future<void> save(AppSettings settings) async {}
}

class _MemoryScreenshotActions implements ScreenshotActionService {
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
