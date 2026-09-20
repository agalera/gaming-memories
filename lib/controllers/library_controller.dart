import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/library.dart';
import '../providers/screenshot_provider.dart';
import '../services/config_store.dart';
import '../services/library_scanner.dart';
import '../services/screenshot_action_service.dart';

enum LibraryView { timeline, platform, album, subAlbum, settings }

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.configStore,
    required this.scanner,
    required this.providers,
    this.screenshotActions = const NativeScreenshotActionService(),
  });

  final ConfigStore configStore;
  final LibraryScanner scanner;
  final List<ScreenshotProvider> providers;
  final ScreenshotActionService screenshotActions;

  AppSettings settings = const AppSettings.defaults();
  MediaLibrary library = const MediaLibrary.empty();
  LibraryView view = LibraryView.timeline;
  String? selectedPlatform;
  String? selectedGame;
  String? selectedSubAlbumPath;
  MediaItem? selectedMedia;
  bool isInitializing = true;
  bool isBusy = false;
  String? message;
  String? error;
  String? progressMessage;
  double? progressValue;
  int notificationRevision = 0;

  List<MediaItem> get visibleMedia {
    if (view == LibraryView.platform && selectedPlatform != null) {
      return library.platformTimeline(selectedPlatform!);
    }

    if (view == LibraryView.album &&
        selectedPlatform != null &&
        selectedGame != null) {
      return library.album(selectedPlatform!, selectedGame!)?.allMedia ??
          const [];
    }

    if (view == LibraryView.subAlbum &&
        selectedPlatform != null &&
        selectedGame != null &&
        selectedSubAlbumPath != null) {
      return library
              .album(selectedPlatform!, selectedGame!)
              ?.subAlbum(selectedSubAlbumPath!)
              ?.allMedia ??
          const [];
    }

    return library.timeline;
  }

  String get pageTitle {
    return switch (view) {
      LibraryView.timeline => 'Timeline',
      LibraryView.platform => selectedPlatform ?? 'Platform',
      LibraryView.album => selectedGame ?? 'Album',
      LibraryView.subAlbum => _selectedSubAlbum?.name ?? 'Sub-album',
      LibraryView.settings => 'Settings',
    };
  }

  String get pageDescription {
    return switch (view) {
      LibraryView.timeline => 'All media, from newest to oldest',
      LibraryView.platform => 'Platform timeline, from newest to oldest',
      LibraryView.album => selectedPlatform ?? '',
      LibraryView.subAlbum => [?selectedPlatform, ?selectedGame].join('  •  '),
      LibraryView.settings => 'Library and provider setup',
    };
  }

  SubAlbum? get _selectedSubAlbum {
    if (selectedPlatform == null ||
        selectedGame == null ||
        selectedSubAlbumPath == null) {
      return null;
    }

    return library
        .album(selectedPlatform!, selectedGame!)
        ?.subAlbum(selectedSubAlbumPath!);
  }

  Future<void> initialize() async {
    try {
      settings = await configStore.load();
      library = await scanner.scan(settings.outputPath);
    } catch (exception) {
      _setError('Could not load the library: $exception');
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  void showTimeline() {
    selectedMedia = null;
    view = LibraryView.timeline;
    selectedPlatform = null;
    selectedGame = null;
    selectedSubAlbumPath = null;
    notifyListeners();
  }

  void showAlbum(String platform, String game) {
    selectedMedia = null;
    view = LibraryView.album;
    selectedPlatform = platform;
    selectedGame = game;
    selectedSubAlbumPath = null;
    notifyListeners();
  }

  void showSubAlbum(String platform, String game, String subAlbumPath) {
    selectedMedia = null;
    view = LibraryView.subAlbum;
    selectedPlatform = platform;
    selectedGame = game;
    selectedSubAlbumPath = subAlbumPath;
    notifyListeners();
  }

  void showPlatform(String platform) {
    selectedMedia = null;
    view = LibraryView.platform;
    selectedPlatform = platform;
    selectedGame = null;
    selectedSubAlbumPath = null;
    notifyListeners();
  }

  void showSettings() {
    selectedMedia = null;
    view = LibraryView.settings;
    notifyListeners();
  }

  void showMedia(MediaItem media) {
    selectedMedia = media;
    notifyListeners();
  }

  void closeMedia() {
    selectedMedia = null;
    notifyListeners();
  }

  Future<void> openMediaLocation(MediaItem media) async {
    await _runScreenshotAction(
      () => screenshotActions.openLocation(media.path),
      success: 'Opened in the file manager.',
      failure: 'Could not open the file manager',
    );
  }

  Future<void> copyMediaImage(MediaItem media) async {
    await _runScreenshotAction(
      () => screenshotActions.copyImage(media.path),
      success: 'Image copied.',
      failure: 'Could not copy the image',
    );
  }

  Future<void> copyMediaPath(MediaItem media) async {
    await _runScreenshotAction(
      () => screenshotActions.copyPath(media.path),
      success: 'Path copied.',
      failure: 'Could not copy the path',
    );
  }

  void previewTheme(AppThemeMode themeMode) {
    settings = settings.copyWith(themeMode: themeMode);
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings next) async {
    await _run(() async {
      _setProgress('Saving settings…');
      await configStore.save(next);
      settings = next;
      _setProgress('Refreshing the library…');
      library = await scanner.scan(settings.outputPath);
      _setMessage('Settings saved.');
    });
  }

  Future<void> refresh() async {
    await _run(() async {
      _setProgress('Refreshing the library…');
      library = await scanner.scan(settings.outputPath);
      _setMessage('Library refreshed.');
    });
  }

  Future<void> collect() async {
    await _run(() async {
      final results = <ImportResult>[];
      final enabledProviders = providers
          .where((provider) => provider.isEnabled(settings))
          .toList(growable: false);
      for (final provider in enabledProviders) {
        _setProgress('Preparing ${provider.name}…');
        results.add(
          await provider.collect(
            settings,
            onProgress: (progress) {
              _setProgress(progress.message, value: progress.value);
            },
          ),
        );
      }
      _setProgress('Refreshing the library…');
      library = await scanner.scan(settings.outputPath);
      final imported = results.fold(0, (sum, result) => sum + result.imported);
      final skipped = results.fold(0, (sum, result) => sum + result.skipped);
      if (results.isEmpty) {
        _setMessage('Enable a provider in Settings first.');
      } else if (imported == 0) {
        _setMessage('No new media. $skipped already in the library.');
      } else {
        _setMessage('Imported $imported media files. Skipped $skipped.');
      }
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
      _setError(exception.toString().replaceFirst('FileSystemException: ', ''));
    } finally {
      isBusy = false;
      progressMessage = null;
      progressValue = null;
      notifyListeners();
    }
  }

  void _setProgress(String nextMessage, {double? value}) {
    progressMessage = nextMessage;
    progressValue = value;
    notifyListeners();
  }

  Future<void> _runScreenshotAction(
    Future<void> Function() action, {
    required String success,
    required String failure,
  }) async {
    message = null;
    error = null;

    try {
      await action();
      _setMessage(success);
    } catch (exception) {
      _setError('$failure: $exception');
    }
    notifyListeners();
  }

  void _setMessage(String value) {
    message = value;
    error = null;
    notificationRevision++;
  }

  void _setError(String value) {
    error = value;
    message = null;
    notificationRevision++;
  }
}
