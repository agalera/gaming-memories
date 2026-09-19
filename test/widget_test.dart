import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:gaming_memories/app.dart';
import 'package:gaming_memories/controllers/library_controller.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/models/library.dart';
import 'package:gaming_memories/services/config_store.dart';
import 'package:gaming_memories/services/library_scanner.dart';
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

    expect(find.text('Screenshot library'), findsOneWidget);
    expect(find.text('Color mode'), findsOneWidget);
    expect(find.text('Diablo IV'), findsOneWidget);

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
    controller.library = ScreenshotLibrary(
      albums: [
        GameAlbum(
          platform: 'PC',
          game: 'Diablo IV',
          screenshots: [
            ScreenshotItem(
              path: p.join(directory.path, 'missing.jpg'),
              platform: 'PC',
              game: 'Diablo IV',
              capturedAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(GamingMemoriesApp(controller: controller));
    await tester.pump();

    await tester.tap(find.text('PC'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(controller.view, LibraryView.platform);
    expect(controller.pageTitle, 'PC');
    expect(controller.visibleScreenshots, hasLength(1));

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
