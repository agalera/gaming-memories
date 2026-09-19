import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/app.dart';
import 'package:gaming_memories/controllers/library_controller.dart';
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
}
