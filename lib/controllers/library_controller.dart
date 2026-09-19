import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/library.dart';
import '../providers/diablo_iv_provider.dart';
import '../services/config_store.dart';
import '../services/library_scanner.dart';

enum LibraryView { timeline, platform, album, settings }

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.configStore,
    required this.scanner,
    required this.diabloIVProvider,
  });

  final ConfigStore configStore;
  final LibraryScanner scanner;
  final DiabloIVProvider diabloIVProvider;

  AppSettings settings = const AppSettings.defaults();
  ScreenshotLibrary library = const ScreenshotLibrary.empty();
  LibraryView view = LibraryView.timeline;
  String? selectedPlatform;
  String? selectedGame;
  bool isInitializing = true;
  bool isBusy = false;
  String? message;
  String? error;

  List<ScreenshotItem> get visibleScreenshots {
    if (view == LibraryView.platform && selectedPlatform != null) {
      return library.platformTimeline(selectedPlatform!);
    }

    if (view == LibraryView.album &&
        selectedPlatform != null &&
        selectedGame != null) {
      return library.album(selectedPlatform!, selectedGame!)?.screenshots ??
          const [];
    }

    return library.timeline;
  }

  String get pageTitle {
    return switch (view) {
      LibraryView.timeline => 'Timeline',
      LibraryView.platform => selectedPlatform ?? 'Platform',
      LibraryView.album => selectedGame ?? 'Album',
      LibraryView.settings => 'Settings',
    };
  }

  String get pageDescription {
    return switch (view) {
      LibraryView.timeline => 'All screenshots, from newest to oldest',
      LibraryView.platform => 'Platform timeline, from newest to oldest',
      LibraryView.album => selectedPlatform ?? '',
      LibraryView.settings => 'Library and provider setup',
    };
  }

  Future<void> initialize() async {
    try {
      settings = await configStore.load();
      library = await scanner.scan(settings.outputPath);
    } catch (exception) {
      error = 'Could not load the library: $exception';
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  void showTimeline() {
    view = LibraryView.timeline;
    selectedPlatform = null;
    selectedGame = null;
    notifyListeners();
  }

  void showAlbum(String platform, String game) {
    view = LibraryView.album;
    selectedPlatform = platform;
    selectedGame = game;
    notifyListeners();
  }

  void showPlatform(String platform) {
    view = LibraryView.platform;
    selectedPlatform = platform;
    selectedGame = null;
    notifyListeners();
  }

  void showSettings() {
    view = LibraryView.settings;
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings next) async {
    await _run(() async {
      await configStore.save(next);
      settings = next;
      library = await scanner.scan(settings.outputPath);
      message = 'Settings saved.';
    });
  }

  Future<void> refresh() async {
    await _run(() async {
      library = await scanner.scan(settings.outputPath);
      message = 'Library refreshed.';
    });
  }

  Future<void> collect() async {
    await _run(() async {
      final result = await diabloIVProvider.collect(settings);
      library = await scanner.scan(settings.outputPath);
      message = result.imported == 0
          ? 'No new screenshots. ${result.skipped} already in the library.'
          : 'Imported ${result.imported} screenshots. Skipped ${result.skipped}.';
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    isBusy = true;
    message = null;
    error = null;
    notifyListeners();

    try {
      await action();
    } catch (exception) {
      error = exception.toString().replaceFirst('FileSystemException: ', '');
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}
