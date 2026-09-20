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
  test('selects a platform and shows its media by date', () {
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
    expect(controller.visibleMedia, [newer, older]);
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
