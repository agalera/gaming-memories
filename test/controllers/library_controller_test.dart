import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/controllers/library_controller.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/models/library.dart';
import 'package:gaming_memories/providers/screenshot_provider.dart';
import 'package:gaming_memories/services/config_store.dart';
import 'package:gaming_memories/services/library_scanner.dart';
import 'package:gaming_memories/services/screenshot_action_service.dart';

void main() {
  test('selects a platform and shows its screenshots by date', () {
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [],
    );
    final older = ScreenshotItem(
      path: '/pc-old.jpg',
      platform: 'PC',
      game: 'Diablo IV',
      capturedAt: DateTime(2026, 1, 1),
    );
    final newer = ScreenshotItem(
      path: '/pc-new.jpg',
      platform: 'PC',
      game: 'Minecraft',
      capturedAt: DateTime(2026, 2, 1),
    );
    final console = ScreenshotItem(
      path: '/console.jpg',
      platform: 'PlayStation 5',
      game: 'Astro Bot',
      capturedAt: DateTime(2026, 3, 1),
    );
    controller.library = ScreenshotLibrary(
      albums: [
        GameAlbum(platform: 'PC', game: 'Diablo IV', screenshots: [older]),
        GameAlbum(platform: 'PC', game: 'Minecraft', screenshots: [newer]),
        GameAlbum(
          platform: 'PlayStation 5',
          game: 'Astro Bot',
          screenshots: [console],
        ),
      ],
    );

    controller.showPlatform('PC');

    expect(controller.view, LibraryView.platform);
    expect(controller.pageTitle, 'PC');
    expect(controller.selectedGame, isNull);
    expect(controller.visibleScreenshots, [newer, older]);
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

  test('returns from a screenshot to the same library view', () {
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [],
    );
    final screenshot = ScreenshotItem(
      path: '/pc.jpg',
      platform: 'PC',
      game: 'Diablo IV',
      capturedAt: DateTime(2026, 1, 1),
    );

    controller.showPlatform('PC');
    controller.showScreenshot(screenshot);

    expect(controller.view, LibraryView.platform);
    expect(controller.selectedPlatform, 'PC');
    expect(controller.selectedScreenshot, same(screenshot));

    controller.closeScreenshot();

    expect(controller.view, LibraryView.platform);
    expect(controller.selectedPlatform, 'PC');
    expect(controller.selectedScreenshot, isNull);
  });

  test('runs screenshot file actions and reports success', () async {
    final actions = _FakeScreenshotActions();
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      providers: const [],
      screenshotActions: actions,
    );
    final screenshot = ScreenshotItem(
      path: '/pc.jpg',
      platform: 'PC',
      game: 'Diablo IV',
      capturedAt: DateTime(2026, 1, 1),
    );

    await controller.openScreenshotLocation(screenshot);
    await controller.copyScreenshotImage(screenshot);
    await controller.copyScreenshotPath(screenshot);

    expect(actions.openedPaths, ['/pc.jpg']);
    expect(actions.copiedImages, ['/pc.jpg']);
    expect(actions.copiedPaths, ['/pc.jpg']);
    expect(controller.message, 'Path copied.');
    expect(controller.error, isNull);
  });
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
