import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/controllers/library_controller.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/models/library.dart';
import 'package:gaming_memories/providers/screenshot_provider.dart';
import 'package:gaming_memories/services/config_store.dart';
import 'package:gaming_memories/services/library_scanner.dart';

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
