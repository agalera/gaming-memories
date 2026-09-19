import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/controllers/library_controller.dart';
import 'package:gaming_memories/models/library.dart';
import 'package:gaming_memories/providers/diablo_iv_provider.dart';
import 'package:gaming_memories/services/config_store.dart';
import 'package:gaming_memories/services/library_scanner.dart';

void main() {
  test('selects a platform and shows its screenshots by date', () {
    final controller = LibraryController(
      configStore: const ConfigStore(filePath: 'unused'),
      scanner: const LibraryScanner(),
      diabloIVProvider: const DiabloIVProvider(),
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
}
