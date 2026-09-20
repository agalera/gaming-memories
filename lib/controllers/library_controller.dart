import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../models/library.dart';
import '../providers/screenshot_provider.dart';
import '../services/config_store.dart';
import '../services/folder_access_service.dart';
import '../services/library_scanner.dart';
import '../services/library_watcher.dart';
import '../services/provider_paths.dart';
import '../services/screenshot_action_service.dart';
import '../services/timeline_cache.dart';

enum LibraryView { timeline, platform, album, subAlbum, settings }

enum NotificationKind { success, warning, error }

enum FolderAuthorizationStatus {
  notRequired,
  ready,
  needsAuthorization,
  unavailable,
}

enum SettingsFolderTarget {
  library,
  battleNetCustom,
  battleNetAutomatic,
  guildWars2Custom,
  hytaleCustom,
  hytaleAutomatic,
  minecraftCustom,
  minecraftAutomatic,
  nintendoSwitch2Custom,
  playStation4Custom,
  playStation5Custom,
  steamCustom,
  steamAutomatic,
}

class AutomaticFolderCandidate {
  const AutomaticFolderCandidate({required this.name, required this.path});

  final String name;
  final String path;
}

class FolderAuthorization {
  const FolderAuthorization(this.status, {this.path});

  const FolderAuthorization.notRequired()
    : status = FolderAuthorizationStatus.notRequired,
      path = null;

  const FolderAuthorization.needsAuthorization({this.path})
    : status = FolderAuthorizationStatus.needsAuthorization;

  final FolderAuthorizationStatus status;
  final String? path;

  bool get isReady => status == FolderAuthorizationStatus.ready;
}

class FolderChoiceResult {
  const FolderChoiceResult._({
    required this.saved,
    required this.cancelled,
    this.path,
    this.message,
  });

  const FolderChoiceResult.success(String path)
    : this._(saved: true, cancelled: false, path: path);

  const FolderChoiceResult.cancelled() : this._(saved: false, cancelled: true);

  const FolderChoiceResult.failure(String message)
    : this._(saved: false, cancelled: false, message: message);

  final bool saved;
  final bool cancelled;
  final String? path;
  final String? message;
}

class AppNotification {
  const AppNotification({
    required this.revision,
    required this.message,
    required this.kind,
  });

  final int revision;
  final String message;
  final NotificationKind kind;
}

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.configStore,
    required this.scanner,
    required this.providers,
    this.timelineCache = const TimelineCache.disabled(),
    this.libraryWatcher = const NativeLibraryWatcher(),
    this.folderAccess = const PathFolderAccessService(),
    this.providerPaths = const ProviderPathResolver(),
    this.screenshotActions = const NativeScreenshotActionService(),
  });

  final ConfigStore configStore;
  final LibraryScanner scanner;
  final List<ScreenshotProvider> providers;
  final TimelineCache timelineCache;
  final LibraryWatcher libraryWatcher;
  final FolderAccessService folderAccess;
  final ProviderPathResolver providerPaths;
  final ScreenshotActionService screenshotActions;

  AppSettings settings = const AppSettings.defaults();
  MediaLibrary library = const MediaLibrary.empty();
  List<MediaItem> timelineMedia = const [];
  List<LibraryFolder> folderTree = const [];
  FolderListing folderListing = const FolderListing.empty();
  LibraryView view = LibraryView.timeline;
  String? selectedPlatform;
  String? selectedGame;
  String? selectedSubAlbumPath;
  MediaItem? selectedMedia;
  bool isInitializing = true;
  bool isAlbumTreeLoading = false;
  bool isBusy = false;
  bool isTimelineRefreshing = false;
  bool isViewLoading = false;
  String? message;
  String? error;
  NotificationKind? notificationKind;
  String? progressMessage;
  double? progressValue;
  int notificationRevision = 0;
  final List<AppNotification> _notifications = [];
  Map<String, String> _providerValidationErrors = const {};
  final Map<String, FolderAuthorization> _folderAuthorizations = {};
  FolderAccessLease? _libraryLease;
  Future<void>? _timelineRefresh;
  String? _timelineRefreshPath;
  StreamSubscription<LibraryChange>? _libraryWatchSubscription;
  String? _watchedLibraryPath;
  int _libraryWatchGeneration = 0;
  final Map<String, LibraryChange> _pendingLibraryChanges = {};
  Timer? _libraryChangeTimer;
  Timer? _libraryWatchRecoveryTimer;
  Future<void>? _libraryChangeRefresh;
  int _folderRequest = 0;
  bool _disposed = false;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  Map<String, String> get providerValidationErrors => _providerValidationErrors;

  String? providerValidationError(String providerName) =>
      _providerValidationErrors[providerName];

  bool get usesPersistentFolderAccess => folderAccess.requiresPersistentGrant;

  bool get libraryNeedsAuthorization {
    return settings.outputPath.trim().isNotEmpty &&
        folderAuthorization(FolderGrantIds.library).status !=
            FolderAuthorizationStatus.ready &&
        usesPersistentFolderAccess;
  }

  FolderAuthorization folderAuthorization(String id) {
    if (!usesPersistentFolderAccess) {
      return const FolderAuthorization.notRequired();
    }
    return _folderAuthorizations[id] ??
        const FolderAuthorization.needsAuthorization();
  }

  List<AutomaticFolderCandidate> automaticFolderCandidates(
    SettingsFolderTarget target,
  ) {
    final paths = switch (target) {
      SettingsFolderTarget.battleNetAutomatic =>
        providerPaths.battleNetRootCandidates(),
      SettingsFolderTarget.steamAutomatic =>
        providerPaths.steamUserdataCandidates(),
      SettingsFolderTarget.hytaleAutomatic => [
        ?providerPaths.hytaleScreenshots(),
      ],
      SettingsFolderTarget.minecraftAutomatic =>
        providerPaths.minecraftScreenshots(),
      _ => const <String>[],
    };
    return paths
        .map(
          (path) => AutomaticFolderCandidate(
            name: p.basename(p.normalize(path)),
            path: path,
          ),
        )
        .toList(growable: false);
  }

  List<MediaItem> get visibleMedia {
    if (view == LibraryView.album || view == LibraryView.subAlbum) {
      return folderListing.media;
    }
    if (view == LibraryView.platform) {
      return const [];
    }
    return timelineMedia.isEmpty ? library.timeline : timelineMedia;
  }

  List<LibraryFolder> get platformFolders {
    if (folderTree.isNotEmpty) {
      return folderTree;
    }
    return _foldersFromLibrary();
  }

  List<LibraryFolder> get gameFolders {
    final platform = selectedPlatform;
    if (platform == null) {
      return const [];
    }
    for (final folder in platformFolders) {
      if (folder.name == platform) {
        return folder.children;
      }
    }
    return const [];
  }

  String get pageTitle {
    return switch (view) {
      LibraryView.timeline => 'Timeline',
      LibraryView.platform => selectedPlatform ?? 'Platform',
      LibraryView.album => selectedGame ?? 'Album',
      LibraryView.subAlbum =>
        _selectedSubAlbum?.name ??
            p
                .basename(selectedSubAlbumPath ?? '')
                .replaceAll(RegExp(r'[/\\]+$'), ''),
      LibraryView.settings => 'Settings',
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

  List<LibraryFolder> _foldersFromLibrary() {
    final groups = <String, List<LibraryFolder>>{};
    for (final album in library.albums) {
      groups
          .putIfAbsent(album.platform, () => [])
          .add(
            LibraryFolder(
              name: album.game,
              path: p.join(settings.outputPath, album.platform, album.game),
              relativePath: album.game,
              children: album.subAlbums
                  .map((folder) => _folderFromSubAlbum(album, folder))
                  .toList(growable: false),
            ),
          );
    }
    return groups.entries
        .map(
          (entry) => LibraryFolder(
            name: entry.key,
            path: p.join(settings.outputPath, entry.key),
            children: entry.value,
          ),
        )
        .toList(growable: false);
  }

  LibraryFolder _folderFromSubAlbum(GameAlbum album, SubAlbum folder) {
    return LibraryFolder(
      name: folder.name,
      path: p.join(
        settings.outputPath,
        album.platform,
        album.game,
        folder.relativePath,
      ),
      relativePath: folder.relativePath,
      children: folder.children
          .map((child) => _folderFromSubAlbum(album, child))
          .toList(growable: false),
    );
  }

  FolderListing _fallbackGameListing(String platform, String game) {
    final album = library.album(platform, game);
    final gameFolder = gameFolders
        .where((folder) => folder.name == game)
        .firstOrNull;
    return FolderListing(
      folders: gameFolder?.children ?? const [],
      media: album?.media ?? const [],
    );
  }

  FolderListing _fallbackSubAlbumListing(
    String platform,
    String game,
    String relativePath,
  ) {
    final folder = library.album(platform, game)?.subAlbum(relativePath);
    return FolderListing(
      folders:
          folder?.children
              .map(
                (child) => LibraryFolder(
                  name: child.name,
                  path: p.join(
                    settings.outputPath,
                    platform,
                    game,
                    child.relativePath,
                  ),
                  relativePath: child.relativePath,
                ),
              )
              .toList(growable: false) ??
          const [],
      media: folder?.media ?? const [],
    );
  }

  Future<void> _loadSelectedFolder() async {
    if (settings.outputPath.trim().isEmpty ||
        selectedPlatform == null ||
        selectedGame == null ||
        (view != LibraryView.album && view != LibraryView.subAlbum)) {
      return;
    }

    final request = ++_folderRequest;
    final platform = selectedPlatform!;
    final game = selectedGame!;
    final subAlbumPath = selectedSubAlbumPath ?? '';
    isViewLoading = true;
    notifyListeners();
    try {
      final listing = await scanner.folderContents(
        settings.outputPath,
        platform,
        game,
        subAlbumPath: subAlbumPath,
        onUpdate: (listing) {
          if (request == _folderRequest && !_disposed) {
            folderListing = listing;
            notifyListeners();
          }
        },
      );
      if (request == _folderRequest && !_disposed) {
        folderListing = listing;
        notifyListeners();
        await _prepareSelectedFolder(request, listing);
      }
    } catch (exception) {
      if (request == _folderRequest && !_disposed) {
        _setError('Could not load this folder: $exception');
      }
    } finally {
      if (request == _folderRequest && !_disposed) {
        isViewLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _prepareSelectedFolder(
    int request,
    FolderListing listing,
  ) async {
    try {
      await scanner.prepareFolderContents(
        listing,
        isCancelled: () => request != _folderRequest || _disposed,
        onUpdate: (prepared) {
          if (request == _folderRequest && !_disposed) {
            folderListing = prepared;
            notifyListeners();
          }
        },
      );
    } catch (exception) {
      if (request == _folderRequest && !_disposed) {
        _setError('Could not prepare media previews: $exception');
        notifyListeners();
      }
    }
  }

  Future<void> initialize() async {
    var canLoadLibrary = false;
    isAlbumTreeLoading = true;
    try {
      settings = await configStore.load();
      if (usesPersistentFolderAccess) {
        var changed = await _restoreLibraryGrant();
        changed = await _restoreProviderGrants() || changed;
        final validation = await _validateEnabledProviders(settings);
        settings = validation.settings;
        _providerValidationErrors = Map.unmodifiable(validation.errors);
        changed = validation.disabledProviders.isNotEmpty || changed;
        if (changed) {
          await configStore.save(settings);
        }
        _showProviderValidationErrors(validation.errors);
      } else {
        final validation = await _validateEnabledProviders(settings);
        settings = validation.settings;
        _providerValidationErrors = Map.unmodifiable(validation.errors);
        if (validation.disabledProviders.isNotEmpty) {
          await configStore.save(settings);
        }
        _showProviderValidationErrors(validation.errors);
      }

      if (!libraryNeedsAuthorization) {
        final results = await Future.wait<Object>([
          _loadInitialFolderTree(settings.outputPath),
          timelineCache.load(settings.outputPath),
        ]);
        folderTree = results[0] as List<LibraryFolder>;
        timelineMedia = results[1] as List<MediaItem>;
        library = const MediaLibrary.empty();
        canLoadLibrary = settings.outputPath.trim().isNotEmpty;
      } else {
        timelineMedia = const [];
        folderTree = const [];
        isAlbumTreeLoading = false;
        view = LibraryView.settings;
      }
    } catch (exception) {
      _setError('Could not load the library: $exception');
    } finally {
      isAlbumTreeLoading = false;
      isInitializing = false;
      notifyListeners();
    }
    if (canLoadLibrary) {
      unawaited(_refreshTimeline(showResult: false));
    }
  }

  Future<List<LibraryFolder>> _loadInitialFolderTree(String outputPath) async {
    final folders = await scanner.folderTree(outputPath);
    if (!_disposed) {
      folderTree = folders;
      isAlbumTreeLoading = false;
      notifyListeners();
    }
    return folders;
  }

  Future<bool> _restoreLibraryGrant() async {
    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      _folderAuthorizations[FolderGrantIds.library] =
          const FolderAuthorization.notRequired();
      return false;
    }

    final grant = settings.folderGrants[FolderGrantIds.library];
    if (grant == null || grant.bookmark.isEmpty) {
      _folderAuthorizations[FolderGrantIds.library] =
          FolderAuthorization.needsAuthorization(path: outputPath);
      return false;
    }

    FolderAccessLease? lease;
    try {
      lease = await folderAccess.activate(grant);
      await _ensureWritableDirectory(lease.grant.path);
      final activeGrant = lease.grant;
      _libraryLease = lease;
      lease = null;
      _folderAuthorizations[FolderGrantIds.library] = FolderAuthorization(
        FolderAuthorizationStatus.ready,
        path: activeGrant.path,
      );

      if (_grantChanged(grant, activeGrant) ||
          !_samePath(outputPath, activeGrant.path)) {
        settings = _withGrant(
          settings.copyWith(outputPath: activeGrant.path),
          FolderGrantIds.library,
          activeGrant,
        );
        return true;
      }
    } on FolderAccessException {
      _folderAuthorizations[FolderGrantIds.library] =
          FolderAuthorization.needsAuthorization(path: grant.path);
    } on FileSystemException {
      _folderAuthorizations[FolderGrantIds.library] = FolderAuthorization(
        FolderAuthorizationStatus.unavailable,
        path: grant.path,
      );
    } finally {
      if (lease != null) {
        await folderAccess.release(lease);
      }
    }
    return false;
  }

  Future<bool> _restoreProviderGrants() async {
    var changed = false;
    for (final provider
        in providers.whereType<FolderBackedScreenshotProvider>()) {
      final requirement = provider.folderRequirement(settings);
      if (requirement == null) {
        _folderAuthorizations[provider.folderGrantId] =
            const FolderAuthorization.notRequired();
        continue;
      }
      final grant = settings.folderGrants[requirement.id];
      if (grant == null ||
          grant.bookmark.isEmpty ||
          !_samePath(grant.path, requirement.path)) {
        _folderAuthorizations[requirement.id] =
            FolderAuthorization.needsAuthorization(path: requirement.path);
        continue;
      }

      FolderAccessLease? lease;
      try {
        lease = await folderAccess.activate(grant);
        if (requirement.automatic &&
            !_samePath(lease.grant.path, requirement.path)) {
          _folderAuthorizations[requirement.id] =
              FolderAuthorization.needsAuthorization(path: requirement.path);
          continue;
        }
        await _ensureReadableDirectory(lease.grant.path);
        _folderAuthorizations[requirement.id] = FolderAuthorization(
          FolderAuthorizationStatus.ready,
          path: lease.grant.path,
        );
        if (_grantChanged(grant, lease.grant)) {
          var next = _withGrant(settings, requirement.id, lease.grant);
          if (!requirement.automatic) {
            next = provider.withFolderPath(next, lease.grant.path);
          }
          settings = next;
          changed = true;
        }
      } on FolderAccessException {
        _folderAuthorizations[requirement.id] =
            FolderAuthorization.needsAuthorization(path: grant.path);
      } on FileSystemException {
        _folderAuthorizations[requirement.id] = FolderAuthorization(
          FolderAuthorizationStatus.unavailable,
          path: grant.path,
        );
      } finally {
        if (lease != null) {
          await folderAccess.release(lease);
        }
      }
    }
    return changed;
  }

  void showTimeline() {
    _folderRequest++;
    isViewLoading = false;
    selectedMedia = null;
    view = LibraryView.timeline;
    selectedPlatform = null;
    selectedGame = null;
    selectedSubAlbumPath = null;
    notifyListeners();
  }

  Future<void> loadSubAlbums(String platform, String game) async {
    final gameFolder = folderTree
        .where((folder) => folder.name == platform)
        .expand((folder) => folder.children)
        .where((folder) => folder.name == game)
        .firstOrNull;
    if (gameFolder == null || gameFolder.childrenLoaded) {
      return;
    }

    try {
      final children = await scanner.subAlbumTree(
        settings.outputPath,
        platform,
        game,
      );
      if (_disposed) {
        return;
      }
      folderTree = [
        for (final platformFolder in folderTree)
          if (platformFolder.name == platform)
            LibraryFolder(
              name: platformFolder.name,
              path: platformFolder.path,
              relativePath: platformFolder.relativePath,
              coverPath: platformFolder.coverPath,
              childrenLoaded: platformFolder.childrenLoaded,
              children: [
                for (final folder in platformFolder.children)
                  if (folder.name == game)
                    LibraryFolder(
                      name: folder.name,
                      path: folder.path,
                      relativePath: folder.relativePath,
                      coverPath: folder.coverPath,
                      children: children,
                    )
                  else
                    folder,
              ],
            )
          else
            platformFolder,
      ];
      notifyListeners();
    } catch (exception) {
      if (!_disposed) {
        _setError('Could not load sub-albums: $exception');
        notifyListeners();
      }
    }
  }

  void showAlbum(String platform, String game) {
    selectedMedia = null;
    view = LibraryView.album;
    selectedPlatform = platform;
    selectedGame = game;
    selectedSubAlbumPath = null;
    folderListing = _fallbackGameListing(platform, game);
    notifyListeners();
    unawaited(_loadSelectedFolder());
  }

  void showSubAlbum(String platform, String game, String subAlbumPath) {
    selectedMedia = null;
    view = LibraryView.subAlbum;
    selectedPlatform = platform;
    selectedGame = game;
    selectedSubAlbumPath = subAlbumPath;
    folderListing = _fallbackSubAlbumListing(platform, game, subAlbumPath);
    notifyListeners();
    unawaited(_loadSelectedFolder());
  }

  void showPlatform(String platform) {
    _folderRequest++;
    isViewLoading = false;
    selectedMedia = null;
    view = LibraryView.platform;
    selectedPlatform = platform;
    selectedGame = null;
    selectedSubAlbumPath = null;
    folderListing = const FolderListing.empty();
    notifyListeners();
  }

  void showSettings() {
    _folderRequest++;
    isViewLoading = false;
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

  Future<bool> updateSettings(
    AppSettings next, {
    bool showNotification = true,
    Map<String, String> providerErrors = const {},
  }) async {
    try {
      final validation = await _validateEnabledProviders(
        next,
        knownErrors: providerErrors,
      );
      final validated = validation.settings;
      _providerValidationErrors = Map.unmodifiable(validation.errors);
      final outputChanged = !_samePath(
        settings.outputPath,
        validated.outputPath,
        allowEmpty: true,
      );
      await configStore.save(validated);
      settings = validated;
      if (outputChanged) {
        await _stopLibraryWatch();
      }
      if (usesPersistentFolderAccess && outputChanged) {
        await _releaseLibraryLease();
      }
      _refreshAuthorizationStates();
      if (showNotification) {
        if (validation.disabledProviders.isEmpty) {
          _setMessage('Settings saved.');
        } else {
          _setError(_providerValidationMessage(validation.errors));
        }
      }
      notifyListeners();
      if (outputChanged && !libraryNeedsAuthorization) {
        await _loadLibrarySnapshot();
        unawaited(_refreshTimeline(showResult: false));
      }
      return true;
    } catch (exception) {
      _setError('Could not save settings: $exception');
      notifyListeners();
      return false;
    }
  }

  Future<String?> providerConfigurationError(
    String providerName,
    AppSettings value,
  ) async {
    for (final provider in providers) {
      if (provider.name == providerName) {
        return _providerConfigurationError(provider, value);
      }
    }
    return null;
  }

  Future<_ProviderValidation> _validateEnabledProviders(
    AppSettings candidate, {
    Map<String, String> knownErrors = const {},
  }) async {
    var validated = candidate;
    final errors = <String, String>{};
    for (final provider in providers) {
      if (!provider.isEnabled(validated) ||
          !_supportsProviderSettings(provider.name)) {
        continue;
      }
      final error =
          knownErrors[provider.name] ??
          await _providerConfigurationError(provider, validated);
      if (error == null) {
        continue;
      }
      validated = _withProviderEnabled(validated, provider.name, false);
      errors[provider.name] = error;
    }
    return _ProviderValidation(validated, errors);
  }

  Future<String?> _providerConfigurationError(
    ScreenshotProvider provider,
    AppSettings candidate,
  ) async {
    if (provider case FolderBackedScreenshotProvider folderProvider) {
      final requirement = folderProvider.folderRequirement(candidate);
      if (requirement == null) {
        if (provider.name == 'Nintendo Switch 2' && Platform.isLinux) {
          return null;
        }
        return 'No supported ${provider.name} folder is configured.';
      }
      if (usesPersistentFolderAccess) {
        final authorization = folderAuthorization(requirement.id);
        if (!authorization.isReady ||
            !_samePath(authorization.path ?? '', requirement.path)) {
          return 'Folder access is required for ${provider.name}.';
        }
      } else if (!await _providerFolderExists(provider, requirement)) {
        return '${provider.name} folder does not exist.';
      }
    }
    if (provider is ProviderConfigurationValidator) {
      return (provider as ProviderConfigurationValidator).configurationError(
        candidate,
      );
    }
    return null;
  }

  Future<bool> _providerFolderExists(
    ScreenshotProvider provider,
    ProviderFolderRequirement requirement,
  ) async {
    if (await Directory(requirement.path).exists()) {
      return true;
    }
    if (!requirement.automatic) {
      return false;
    }
    final candidates = switch (provider.name) {
      'Battle.net' => providerPaths.battleNetRootCandidates(),
      'Hytale' => [providerPaths.hytaleScreenshots()],
      'Minecraft' => providerPaths.minecraftScreenshots(),
      'Steam' => providerPaths.steamUserdataCandidates(),
      _ => <String?>[],
    };
    for (final path in candidates.whereType<String>()) {
      if (await Directory(path).exists()) {
        return true;
      }
    }
    return false;
  }

  AppSettings _withProviderEnabled(
    AppSettings value,
    String providerName,
    bool enabled,
  ) => switch (providerName) {
    'Battle.net' => value.copyWith(
      battleNet: value.battleNet.copyWith(enabled: enabled),
    ),
    'Guild Wars 2' => value.copyWith(
      guildWars2: value.guildWars2.copyWith(enabled: enabled),
    ),
    'Hytale' => value.copyWith(hytale: value.hytale.copyWith(enabled: enabled)),
    'Minecraft' => value.copyWith(
      minecraft: value.minecraft.copyWith(enabled: enabled),
    ),
    'Nintendo Switch 2' => value.copyWith(
      nintendoSwitch2: value.nintendoSwitch2.copyWith(enabled: enabled),
    ),
    'PlayStation 4' => value.copyWith(
      playStation4: value.playStation4.copyWith(enabled: enabled),
    ),
    'PlayStation 5' => value.copyWith(
      playStation5: value.playStation5.copyWith(enabled: enabled),
    ),
    'Steam' => value.copyWith(steam: value.steam.copyWith(enabled: enabled)),
    _ => value,
  };

  bool _supportsProviderSettings(String providerName) => switch (providerName) {
    'Battle.net' ||
    'Guild Wars 2' ||
    'Hytale' ||
    'Minecraft' ||
    'Nintendo Switch 2' ||
    'PlayStation 4' ||
    'PlayStation 5' ||
    'Steam' => true,
    _ => false,
  };

  void _showProviderValidationErrors(Map<String, String> errors) {
    if (errors.isNotEmpty) {
      _setError(_providerValidationMessage(errors));
    }
  }

  String _providerValidationMessage(Map<String, String> errors) {
    if (errors.length == 1) {
      final error = errors.entries.single;
      return '${error.key} was disabled: ${error.value}';
    }
    final details = errors.entries
        .map((error) => '${error.key}: ${error.value}')
        .join(' ');
    return 'Invalid providers were disabled. $details';
  }

  Future<FolderChoiceResult> chooseFolder(
    SettingsFolderTarget target, {
    String? initialPath,
  }) async {
    final specification = _folderSpecification(target, initialPath);
    if (specification == null) {
      return const FolderChoiceResult.failure(
        'No supported automatic folder is available on this platform.',
      );
    }

    FolderAccessLease? lease;
    try {
      lease = await folderAccess.choose(specification.request);
      if (lease == null) {
        return const FolderChoiceResult.cancelled();
      }

      if (specification.expectedPath != null &&
          !_samePath(lease.grant.path, specification.expectedPath!)) {
        await folderAccess.release(lease);
        lease = null;
        return FolderChoiceResult.failure(
          specification.pathMismatchMessage ??
              'Choose the folder shown by Gaming Memories.',
        );
      }

      if (target == SettingsFolderTarget.library) {
        await _ensureWritableDirectory(lease.grant.path);
      } else {
        await _ensureReadableDirectory(lease.grant.path);
      }

      var next = _settingsWithFolder(target, lease.grant.path);
      if (usesPersistentFolderAccess) {
        next = _withGrant(next, specification.request.id, lease.grant);
      }
      _folderAuthorizations[specification.request.id] = FolderAuthorization(
        FolderAuthorizationStatus.ready,
        path: lease.grant.path,
      );
      final validation = await _validateEnabledProviders(next);
      next = validation.settings;
      _providerValidationErrors = Map.unmodifiable(validation.errors);
      await configStore.save(next);

      final oldLibraryLease = _libraryLease;
      settings = next;

      if (target == SettingsFolderTarget.library) {
        if (usesPersistentFolderAccess) {
          _libraryLease = lease;
          lease = null;
          if (oldLibraryLease != null) {
            await folderAccess.release(oldLibraryLease);
          }
        }
        await _loadLibrarySnapshot();
        unawaited(_refreshTimeline(showResult: false));
      }
      if (validation.disabledProviders.isEmpty) {
        _setMessage('Settings saved.');
      } else {
        _setError(_providerValidationMessage(validation.errors));
      }
      notifyListeners();
      return FolderChoiceResult.success(specification.selectedPath(settings));
    } on FileSystemException catch (exception) {
      return FolderChoiceResult.failure(
        exception.message.isEmpty
            ? 'The selected folder could not be accessed.'
            : exception.message,
      );
    } on FolderAccessException catch (exception) {
      return FolderChoiceResult.failure(exception.message);
    } catch (exception) {
      return FolderChoiceResult.failure(
        'Could not save folder access: $exception',
      );
    } finally {
      if (lease != null) {
        await folderAccess.release(lease);
      }
    }
  }

  _FolderSpecification? _folderSpecification(
    SettingsFolderTarget target,
    String? initialPath,
  ) {
    switch (target) {
      case SettingsFolderTarget.library:
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.library,
            title: 'Choose the media library folder',
            access: FolderGrantAccess.readWrite,
            initialPath:
                _nonEmpty(initialPath) ?? _nonEmpty(settings.outputPath),
          ),
          selectedPath: (settings) => settings.outputPath,
        );
      case SettingsFolderTarget.battleNetCustom:
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.battleNet,
            title: 'Choose the Battle.net or game installation folder',
            access: FolderGrantAccess.readOnly,
            initialPath:
                _nonEmpty(initialPath) ??
                _nonEmpty(settings.battleNet.sourcePath),
          ),
          selectedPath: (settings) => settings.battleNet.sourcePath,
        );
      case SettingsFolderTarget.battleNetAutomatic:
        final candidates = automaticFolderCandidates(target);
        if (candidates.isEmpty) {
          return null;
        }
        final requested = _nonEmpty(initialPath);
        final selected = requested == null
            ? candidates.length == 1
                  ? candidates.single
                  : null
            : candidates
                  .where((candidate) => _samePath(candidate.path, requested))
                  .firstOrNull;
        if (selected == null) {
          return null;
        }
        final candidate = selected.path;
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.battleNet,
            title: 'Allow access to Battle.net screenshots',
            access: FolderGrantAccess.readOnly,
            initialPath: candidate,
            suggestedPath: candidate,
            message:
                'Click Allow Access to grant Gaming Memories access to the “${selected.name}” installation folder.',
          ),
          expectedPath: candidate,
          pathMismatchMessage: 'Choose the Battle.net game installation folder shown by Gaming Memories.',
          selectedPath: (_) => candidate,
        );
      case SettingsFolderTarget.guildWars2Custom:
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.guildWars2,
            title: 'Choose the Guild Wars 2 screenshot folder',
            access: FolderGrantAccess.readOnly,
            initialPath:
                _nonEmpty(initialPath) ??
                _nonEmpty(settings.guildWars2.sourcePath),
          ),
          selectedPath: (settings) => settings.guildWars2.sourcePath,
        );
      case SettingsFolderTarget.hytaleCustom:
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.hytale,
            title: 'Choose the Hytale screenshot folder',
            access: FolderGrantAccess.readOnly,
            initialPath:
                _nonEmpty(initialPath) ?? _nonEmpty(settings.hytale.sourcePath),
          ),
          selectedPath: (settings) => settings.hytale.sourcePath,
        );
      case SettingsFolderTarget.hytaleAutomatic:
        final candidates = automaticFolderCandidates(target);
        if (candidates.isEmpty) {
          return null;
        }
        final candidate = candidates.single.path;
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.hytale,
            title: 'Allow access to Hytale screenshots',
            access: FolderGrantAccess.readOnly,
            initialPath: candidate,
            suggestedPath: candidate,
            message: 'Click Allow Access to grant Gaming Memories access to the “Hytale Screenshots” folder.',
          ),
          expectedPath: candidate,
          pathMismatchMessage: 'Choose the “Hytale Screenshots” folder shown by Gaming Memories.',
          selectedPath: (_) => candidate,
        );
      case SettingsFolderTarget.minecraftCustom:
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.minecraft,
            title: 'Choose the Minecraft screenshot folder',
            access: FolderGrantAccess.readOnly,
            initialPath:
                _nonEmpty(initialPath) ??
                _nonEmpty(settings.minecraft.sourcePath),
          ),
          selectedPath: (settings) => settings.minecraft.sourcePath,
        );
      case SettingsFolderTarget.minecraftAutomatic:
        final candidates = automaticFolderCandidates(target);
        if (candidates.isEmpty) {
          return null;
        }
        final requested = _nonEmpty(initialPath);
        final selected = requested == null
            ? candidates.length == 1
                  ? candidates.single
                  : null
            : candidates
                  .where((candidate) => _samePath(candidate.path, requested))
                  .firstOrNull;
        if (selected == null) {
          return null;
        }
        final candidate = selected.path;
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.minecraft,
            title: 'Allow access to Minecraft screenshots',
            access: FolderGrantAccess.readOnly,
            initialPath: candidate,
            suggestedPath: candidate,
            message:
                'Click Allow Access to grant Gaming Memories access to the “${selected.name}” Minecraft folder.',
          ),
          expectedPath: candidate,
          pathMismatchMessage: 'Choose the Minecraft screenshots folder shown by Gaming Memories.',
          selectedPath: (_) => candidate,
        );
      case SettingsFolderTarget.nintendoSwitch2Custom:
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.nintendoSwitch2,
            title: 'Choose the copied Nintendo Switch 2 album folder',
            access: FolderGrantAccess.readOnly,
            initialPath:
                _nonEmpty(initialPath) ??
                _nonEmpty(settings.nintendoSwitch2.sourcePath),
          ),
          selectedPath: (settings) => settings.nintendoSwitch2.sourcePath,
        );
      case SettingsFolderTarget.playStation4Custom:
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.playStation4,
            title: 'Choose the PlayStation 4 exported media folder',
            access: FolderGrantAccess.readOnly,
            initialPath:
                _nonEmpty(initialPath) ??
                _nonEmpty(settings.playStation4.sourcePath),
          ),
          selectedPath: (settings) => settings.playStation4.sourcePath,
        );
      case SettingsFolderTarget.playStation5Custom:
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.playStation5,
            title: 'Choose the PlayStation 5 exported media folder',
            access: FolderGrantAccess.readOnly,
            initialPath:
                _nonEmpty(initialPath) ??
                _nonEmpty(settings.playStation5.sourcePath),
          ),
          selectedPath: (settings) => settings.playStation5.sourcePath,
        );
      case SettingsFolderTarget.steamCustom:
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.steam,
            title: 'Choose the Steam folder',
            access: FolderGrantAccess.readOnly,
            initialPath:
                _nonEmpty(initialPath) ??
                _nonEmpty(settings.steam.userdataPath),
          ),
          selectedPath: (settings) => settings.steam.userdataPath,
        );
      case SettingsFolderTarget.steamAutomatic:
        final candidates = automaticFolderCandidates(target);
        if (candidates.isEmpty) {
          return null;
        }
        final requested = _nonEmpty(initialPath);
        final selected = requested == null
            ? candidates.length == 1
                  ? candidates.single
                  : null
            : candidates
                  .where((candidate) => _samePath(candidate.path, requested))
                  .firstOrNull;
        if (selected == null) {
          return null;
        }
        final candidate = selected.path;
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: FolderGrantIds.steam,
            title: 'Allow access to Steam screenshots',
            access: FolderGrantAccess.readOnly,
            initialPath: candidate,
            suggestedPath: candidate,
            message:
                'Click Allow Access to grant Gaming Memories access to the “${selected.name}” folder. Do not open a numbered Steam account folder.',
          ),
          expectedPath: candidate,
          pathMismatchMessage: 'Choose Steam’s “userdata” folder, not a numbered account folder.',
          selectedPath: (_) => candidate,
        );
    }
  }

  AppSettings _settingsWithFolder(SettingsFolderTarget target, String path) {
    return switch (target) {
      SettingsFolderTarget.library => settings.copyWith(outputPath: path),
      SettingsFolderTarget.battleNetCustom => settings.copyWith(
        battleNet: settings.battleNet.copyWith(
          enabled: true,
          useCustomPath: true,
          sourcePath: path,
        ),
      ),
      SettingsFolderTarget.battleNetAutomatic => settings.copyWith(
        battleNet: settings.battleNet.copyWith(
          enabled: true,
          useCustomPath: false,
          sourcePath: path,
        ),
      ),
      SettingsFolderTarget.guildWars2Custom => settings.copyWith(
        guildWars2: settings.guildWars2.copyWith(
          enabled: true,
          useCustomPath: true,
          sourcePath: path,
        ),
      ),
      SettingsFolderTarget.hytaleCustom => settings.copyWith(
        hytale: settings.hytale.copyWith(
          enabled: true,
          useCustomPath: true,
          sourcePath: path,
        ),
      ),
      SettingsFolderTarget.hytaleAutomatic => settings.copyWith(
        hytale: settings.hytale.copyWith(
          enabled: true,
          useCustomPath: false,
          sourcePath: path,
        ),
      ),
      SettingsFolderTarget.minecraftCustom => settings.copyWith(
        minecraft: settings.minecraft.copyWith(
          enabled: true,
          useCustomPath: true,
          sourcePath: path,
        ),
      ),
      SettingsFolderTarget.minecraftAutomatic => settings.copyWith(
        minecraft: settings.minecraft.copyWith(
          enabled: true,
          useCustomPath: false,
          sourcePath: path,
        ),
      ),
      SettingsFolderTarget.nintendoSwitch2Custom => settings.copyWith(
        nintendoSwitch2: settings.nintendoSwitch2.copyWith(
          enabled: true,
          useCustomPath: true,
          sourcePath: path,
        ),
      ),
      SettingsFolderTarget.playStation4Custom => settings.copyWith(
        playStation4: settings.playStation4.copyWith(
          enabled: true,
          useCustomPath: true,
          sourcePath: path,
        ),
      ),
      SettingsFolderTarget.playStation5Custom => settings.copyWith(
        playStation5: settings.playStation5.copyWith(
          enabled: true,
          useCustomPath: true,
          sourcePath: path,
        ),
      ),
      SettingsFolderTarget.steamCustom => settings.copyWith(
        steam: settings.steam.copyWith(
          enabled: true,
          useCustomPath: true,
          userdataPath: path,
        ),
      ),
      SettingsFolderTarget.steamAutomatic => settings.copyWith(
        steam: settings.steam.copyWith(
          enabled: true,
          useCustomPath: false,
          userdataPath: path,
        ),
      ),
    };
  }

  Future<void> refresh() async {
    if (libraryNeedsAuthorization) {
      _setWarning(
        'Library folder access is required. Open Settings and allow access.',
      );
      notifyListeners();
      return;
    }
    await _refreshFolderViews();
    unawaited(_refreshTimeline(showResult: true));
  }

  Future<void> collect() async {
    if (!libraryNeedsAuthorization) {
      await _ensureLibraryWatch();
    }
    await _run(() async {
      final results = <ImportResult>[];
      final enabledProviders = providers
          .where((provider) => provider.isEnabled(settings))
          .toList(growable: false);
      for (final provider in enabledProviders) {
        final usesLibraryFolder = provider is FolderBackedScreenshotProvider;
        if (usesLibraryFolder && settings.outputPath.trim().isEmpty) {
          results.add(
            ImportResult.warning(
              provider.name,
              '${provider.name} was skipped because no library folder is selected.',
            ),
          );
          continue;
        }
        if (usesLibraryFolder && libraryNeedsAuthorization) {
          results.add(
            ImportResult.warning(
              provider.name,
              '${provider.name} was skipped because the library folder needs access.',
            ),
          );
          continue;
        }

        _setProgress('Preparing ${provider.name}…');
        results.add(await _collectProviderSafely(provider));
      }
      final imported = results.fold(0, (sum, result) => sum + result.imported);
      final skipped = results.fold(0, (sum, result) => sum + result.skipped);
      final warnings = results
          .map((result) => result.warning)
          .whereType<String>()
          .toList(growable: false);
      if (results.isEmpty) {
        _setMessage('Enable a provider in Settings first.');
      } else if (imported == 0 && warnings.isEmpty) {
        _setMessage('No new media. $skipped already in the library.');
      } else if (imported > 0) {
        _setMessage('Imported $imported media files. Skipped $skipped.');
      } else if (skipped > 0) {
        _setMessage('No new media. $skipped already in the library.');
      }
      for (final warning in warnings) {
        _setWarning(warning);
      }
    });
  }

  Future<void> _loadLibrarySnapshot() async {
    await _stopLibraryWatch();
    final results = await Future.wait<Object>([
      scanner.folderTree(settings.outputPath),
      timelineCache.load(settings.outputPath),
    ]);
    folderTree = results[0] as List<LibraryFolder>;
    timelineMedia = results[1] as List<MediaItem>;
    library = const MediaLibrary.empty();
    folderListing = const FolderListing.empty();
    showTimeline();
  }

  Future<void> _refreshFolderViews() async {
    folderTree = await scanner.folderTree(settings.outputPath);
    if (view == LibraryView.album || view == LibraryView.subAlbum) {
      await _loadSelectedFolder();
    } else if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _refreshTimeline({required bool showResult}) async {
    final requestedPath = settings.outputPath;
    final active = _timelineRefresh;
    if (active != null) {
      final activePath = _timelineRefreshPath;
      await active;
      if (identical(_timelineRefresh, active)) {
        _timelineRefresh = null;
        _timelineRefreshPath = null;
      }
      if (!_disposed &&
          activePath != null &&
          !_samePath(activePath, requestedPath)) {
        await _refreshTimeline(showResult: showResult);
      }
      return;
    }

    final operation = _performTimelineRefresh(showResult: showResult);
    _timelineRefresh = operation;
    _timelineRefreshPath = requestedPath;
    try {
      await operation;
    } finally {
      if (identical(_timelineRefresh, operation)) {
        _timelineRefresh = null;
        _timelineRefreshPath = null;
      }
    }
  }

  Future<void> _performTimelineRefresh({required bool showResult}) async {
    final outputPath = settings.outputPath;
    if (outputPath.trim().isEmpty || libraryNeedsAuthorization) {
      return;
    }

    isTimelineRefreshing = true;
    progressMessage = 'Refreshing the timeline cache…';
    progressValue = null;
    notifyListeners();
    try {
      await _ensureReadableDirectory(expandUserPath(outputPath));
      await _ensureLibraryWatch();
      final nextLibrary = await scanner.scan(outputPath);
      if (_disposed || !_samePath(outputPath, settings.outputPath)) {
        return;
      }
      timelineMedia = nextLibrary.timeline;
      library = const MediaLibrary.empty();
      await timelineCache.save(outputPath, timelineMedia);
      folderTree = await scanner.folderTree(outputPath);
      if (showResult) {
        _setMessage('Timeline refreshed.');
      }
    } catch (exception) {
      if (!_disposed) {
        _setError('Could not refresh the timeline: $exception');
      }
    } finally {
      if (!_disposed) {
        isTimelineRefreshing = false;
        progressMessage = null;
        progressValue = null;
        notifyListeners();
        _scheduleLibraryChangeFlush();
      }
    }
  }

  Future<void> _ensureLibraryWatch() async {
    final outputPath = settings.outputPath.trim();
    if (_disposed || outputPath.isEmpty || libraryNeedsAuthorization) {
      await _stopLibraryWatch();
      return;
    }

    final normalized = _normalizeLibraryPath(outputPath);
    if (_libraryWatchSubscription != null &&
        _watchedLibraryPath != null &&
        _samePath(_watchedLibraryPath!, normalized)) {
      return;
    }

    final generation = ++_libraryWatchGeneration;
    await _libraryWatchSubscription?.cancel();
    _libraryWatchSubscription = null;
    _watchedLibraryPath = null;
    if (_disposed || generation != _libraryWatchGeneration) {
      return;
    }

    try {
      final stream = await libraryWatcher.watch(normalized);
      if (_disposed || generation != _libraryWatchGeneration) {
        await stream.listen(null).cancel();
        return;
      }
      _watchedLibraryPath = normalized;
      _libraryWatchSubscription = stream.listen(
        (change) {
          if (generation == _libraryWatchGeneration) {
            _queueLibraryChange(change);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (generation == _libraryWatchGeneration) {
            _handleLibraryWatchFailure(error, stackTrace);
          }
        },
        onDone: () {
          if (generation == _libraryWatchGeneration) {
            _handleLibraryWatchFailure(
              const FileSystemException('The library watcher stopped.'),
              StackTrace.current,
            );
          }
        },
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      if (generation == _libraryWatchGeneration) {
        _handleLibraryWatchFailure(error, stackTrace);
      }
    }
  }

  Future<void> _stopLibraryWatch() async {
    _libraryWatchGeneration++;
    _libraryChangeTimer?.cancel();
    _libraryChangeTimer = null;
    _libraryWatchRecoveryTimer?.cancel();
    _libraryWatchRecoveryTimer = null;
    _pendingLibraryChanges.clear();
    final subscription = _libraryWatchSubscription;
    _libraryWatchSubscription = null;
    _watchedLibraryPath = null;
    await subscription?.cancel();
  }

  void _handleLibraryWatchFailure(Object error, StackTrace stackTrace) {
    if (_disposed) {
      return;
    }
    _libraryWatchSubscription = null;
    _watchedLibraryPath = null;
    if (!hasListeners) {
      return;
    }
    debugPrint('[Gaming Memories] Library watcher failed: $error\n$stackTrace');
    _libraryWatchRecoveryTimer?.cancel();
    _libraryWatchRecoveryTimer = Timer(
      const Duration(seconds: 1),
      () => unawaited(_recoverLibraryWatch()),
    );
  }

  Future<void> _recoverLibraryWatch() async {
    _libraryWatchRecoveryTimer = null;
    if (_disposed || settings.outputPath.trim().isEmpty) {
      return;
    }
    if (!await Directory(_normalizeLibraryPath(settings.outputPath)).exists()) {
      _libraryWatchRecoveryTimer = Timer(
        const Duration(seconds: 2),
        () => unawaited(_recoverLibraryWatch()),
      );
      return;
    }
    var activeRefresh = _timelineRefresh;
    while (activeRefresh != null) {
      await activeRefresh;
      await Future<void>.delayed(Duration.zero);
      activeRefresh = _timelineRefresh;
    }
    await _refreshTimeline(showResult: false);
  }

  void _queueLibraryChange(LibraryChange change) {
    if (_disposed || !_changeTargetsCurrentLibrary(change)) {
      return;
    }
    final source = _normalizeLibraryPath(change.path);
    final destination = change.destinationPath == null
        ? null
        : _normalizeLibraryPath(change.destinationPath!);
    if (!change.isDirectory &&
        !_isRelevantLibraryFile(source) &&
        (destination == null || !_isRelevantLibraryFile(destination))) {
      return;
    }

    final normalized = LibraryChange(
      kind: change.kind,
      path: source,
      destinationPath: destination,
      isDirectory: change.isDirectory,
    );
    final key =
        '${change.kind.index}|${_pathKey(source)}|'
        '${destination == null ? '' : _pathKey(destination)}';
    _pendingLibraryChanges[key] = normalized;
    _scheduleLibraryChangeFlush();
  }

  void _scheduleLibraryChangeFlush() {
    if (_disposed || _pendingLibraryChanges.isEmpty) {
      return;
    }
    _libraryChangeTimer?.cancel();
    _libraryChangeTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_flushLibraryChanges()),
    );
  }

  Future<void> _flushLibraryChanges() async {
    _libraryChangeTimer = null;
    if (_disposed || _pendingLibraryChanges.isEmpty) {
      return;
    }
    if (isBusy || isTimelineRefreshing || _libraryChangeRefresh != null) {
      _scheduleLibraryChangeFlush();
      return;
    }

    final changes = _pendingLibraryChanges.values.toList(growable: false);
    _pendingLibraryChanges.clear();
    final operation = _applyLibraryChanges(changes);
    _libraryChangeRefresh = operation;
    try {
      await operation;
    } catch (error, stackTrace) {
      debugPrint(
        '[Gaming Memories] Could not apply library changes: '
        '$error\n$stackTrace',
      );
    } finally {
      if (identical(_libraryChangeRefresh, operation)) {
        _libraryChangeRefresh = null;
      }
      _scheduleLibraryChangeFlush();
    }
  }

  Future<void> _applyLibraryChanges(List<LibraryChange> changes) async {
    final outputPath = settings.outputPath;
    final root = _normalizeLibraryPath(outputPath);
    if (_disposed || outputPath.trim().isEmpty) {
      return;
    }

    final directDirectories = <String>{};
    final subtreeDirectories = <String>{};
    final removalPaths = <String>{};
    final changedFiles = <String>{};
    var treeChanged = false;

    void addPresentPath(
      String path, {
      required bool isDirectory,
      required bool scanSubtree,
    }) {
      if (isDirectory) {
        treeChanged = true;
        if (scanSubtree) {
          subtreeDirectories.add(path);
        } else {
          directDirectories.add(path);
        }
        directDirectories.add(p.dirname(path));
      } else if (scanner.isCoverPath(path)) {
        treeChanged = true;
      } else if (scanner.supportsMediaPath(path)) {
        changedFiles.add(_pathKey(path));
        directDirectories.add(p.dirname(path));
      }
    }

    for (final change in changes) {
      final source = _normalizeLibraryPath(change.path);
      final sourceIsDirectory =
          change.isDirectory || _isKnownLibraryDirectory(source);
      if (change.kind == LibraryChangeKind.delete ||
          change.kind == LibraryChangeKind.move) {
        removalPaths.add(source);
        if (sourceIsDirectory) {
          treeChanged = true;
        } else if (scanner.isCoverPath(source)) {
          treeChanged = true;
        }
        directDirectories.add(p.dirname(source));
      }
      if (change.kind == LibraryChangeKind.create ||
          change.kind == LibraryChangeKind.modify) {
        addPresentPath(
          source,
          isDirectory: sourceIsDirectory,
          scanSubtree: change.kind == LibraryChangeKind.create,
        );
      }
      if (change.kind == LibraryChangeKind.move &&
          change.destinationPath != null) {
        addPresentPath(
          _normalizeLibraryPath(change.destinationPath!),
          isDirectory: sourceIsDirectory,
          scanSubtree: sourceIsDirectory,
        );
      }
    }

    if (treeChanged) {
      await _refreshFolderTreePreservingLoaded();
    }

    final mediaByPath = <String, MediaItem>{
      for (final media in timelineMedia) _pathKey(media.path): media,
    };
    var timelineChanged = false;
    for (final removed in removalPaths) {
      final keys = mediaByPath.entries
          .where((entry) => _sameOrWithinPath(removed, entry.value.path))
          .map((entry) => entry.key)
          .toList(growable: false);
      for (final key in keys) {
        mediaByPath.remove(key);
      }
      timelineChanged = keys.isNotEmpty || timelineChanged;
    }

    final subtreeRoots = subtreeDirectories
        .where((candidate) {
          return !subtreeDirectories.any(
            (other) =>
                other != candidate && _sameOrWithinPath(other, candidate),
          );
        })
        .toList(growable: false);
    final expandedSubtrees = <String>[];
    for (final subtree in subtreeRoots) {
      final location = _libraryLocationForDirectory(root, subtree);
      if (location != null) {
        expandedSubtrees.add(subtree);
        await _replaceMediaSubtree(outputPath, subtree, location, mediaByPath);
        timelineChanged = true;
        continue;
      }

      final relative = p.relative(subtree, from: root);
      final parts = p.split(relative);
      if (parts.length == 1 && parts.single != '.') {
        final platform = folderTree
            .where((folder) => folder.name == parts.single)
            .firstOrNull;
        for (final game in platform?.children ?? const <LibraryFolder>[]) {
          expandedSubtrees.add(game.path);
          final gameLocation = _libraryLocationForDirectory(root, game.path);
          if (gameLocation != null) {
            await _replaceMediaSubtree(
              outputPath,
              game.path,
              gameLocation,
              mediaByPath,
            );
            timelineChanged = true;
          }
        }
      }
    }

    final resolvedListings = <String, FolderListing>{};
    for (final directory in directDirectories) {
      if (!_sameOrWithinPath(root, directory) ||
          expandedSubtrees.any(
            (subtree) => _sameOrWithinPath(subtree, directory),
          )) {
        continue;
      }
      final location = _libraryLocationForDirectory(root, directory);
      if (location == null) {
        continue;
      }
      final listing = await scanner.folderContents(
        outputPath,
        location.platform,
        location.game,
        subAlbumPath: location.subAlbumPath,
      );
      final directoryKey = _pathKey(directory);
      final previous = <String, MediaItem>{
        for (final entry in mediaByPath.entries)
          if (_pathKey(p.dirname(entry.value.path)) == directoryKey)
            entry.key: entry.value,
      };
      mediaByPath.removeWhere(
        (_, media) => _pathKey(p.dirname(media.path)) == directoryKey,
      );
      final prepared = <MediaItem>[];
      for (final listed in listing.media) {
        final key = _pathKey(listed.path);
        final existing = previous[key];
        final item =
            existing != null &&
                !changedFiles.contains(key) &&
                _sameSource(existing, listed)
            ? existing
            : await scanner.prepareMediaItem(listed);
        if (item != null) {
          mediaByPath[key] = item;
          prepared.add(item);
        }
      }
      prepared.sort(
        (left, right) => right.capturedAt.compareTo(left.capturedAt),
      );
      resolvedListings[directoryKey] = FolderListing(
        folders: listing.folders,
        media: List.unmodifiable(prepared),
      );
      timelineChanged = true;
    }

    if (_disposed || !_samePath(outputPath, settings.outputPath)) {
      return;
    }
    if (timelineChanged) {
      timelineMedia = mediaByPath.values.toList(growable: false)
        ..sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
      library = const MediaLibrary.empty();
      final selected = selectedMedia;
      if (selected != null) {
        selectedMedia = mediaByPath[_pathKey(selected.path)];
      }
    }
    await _updateVisibleFolderListing(
      root,
      changes,
      resolvedListings,
      mediaByPath,
    );
    notifyListeners();
    if (timelineChanged) {
      await timelineCache.save(outputPath, timelineMedia);
    }
  }

  Future<void> _replaceMediaSubtree(
    String outputPath,
    String directory,
    _LibraryDirectoryLocation location,
    Map<String, MediaItem> mediaByPath,
  ) async {
    mediaByPath.removeWhere(
      (_, media) => _sameOrWithinPath(directory, media.path),
    );
    final media = await scanner.mediaTree(
      outputPath,
      location.platform,
      location.game,
      subAlbumPath: location.subAlbumPath,
    );
    for (final item in media) {
      mediaByPath[_pathKey(item.path)] = item;
    }
  }

  Future<void> _refreshFolderTreePreservingLoaded() async {
    final loadedGames = <String>{
      for (final platform in folderTree)
        for (final game in platform.children)
          if (game.childrenLoaded) '${platform.name}\u0000${game.name}',
    };
    final next = await scanner.folderTree(settings.outputPath);
    final platforms = <LibraryFolder>[];
    for (final platform in next) {
      final games = <LibraryFolder>[];
      for (final game in platform.children) {
        final key = '${platform.name}\u0000${game.name}';
        if (!loadedGames.contains(key)) {
          games.add(game);
          continue;
        }
        final children = await scanner.subAlbumTree(
          settings.outputPath,
          platform.name,
          game.name,
        );
        games.add(
          LibraryFolder(
            name: game.name,
            path: game.path,
            relativePath: game.relativePath,
            coverPath: game.coverPath,
            children: children,
          ),
        );
      }
      platforms.add(
        LibraryFolder(
          name: platform.name,
          path: platform.path,
          relativePath: platform.relativePath,
          coverPath: platform.coverPath,
          childrenLoaded: platform.childrenLoaded,
          children: games,
        ),
      );
    }
    folderTree = platforms;
  }

  Future<void> _updateVisibleFolderListing(
    String root,
    List<LibraryChange> changes,
    Map<String, FolderListing> resolvedListings,
    Map<String, MediaItem> mediaByPath,
  ) async {
    if (view != LibraryView.album && view != LibraryView.subAlbum) {
      return;
    }
    final platform = selectedPlatform;
    final game = selectedGame;
    if (platform == null || game == null) {
      return;
    }
    final directory = p.join(root, platform, game, selectedSubAlbumPath ?? '');
    final affected = changes.any(
      (change) =>
          _sameOrWithinPath(directory, change.path) ||
          _sameOrWithinPath(change.path, directory) ||
          (change.destinationPath != null &&
              (_sameOrWithinPath(directory, change.destinationPath!) ||
                  _sameOrWithinPath(change.destinationPath!, directory))),
    );
    if (!affected) {
      return;
    }

    _folderRequest++;
    isViewLoading = false;
    final directoryKey = _pathKey(directory);
    final resolved = resolvedListings[directoryKey];
    if (resolved != null) {
      folderListing = resolved;
      return;
    }
    final listing = await scanner.folderContents(
      settings.outputPath,
      platform,
      game,
      subAlbumPath: selectedSubAlbumPath ?? '',
    );
    folderListing = FolderListing(
      folders: listing.folders,
      media: [
        for (final item in listing.media) ?mediaByPath[_pathKey(item.path)],
      ],
    );
  }

  bool _changeTargetsCurrentLibrary(LibraryChange change) {
    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      return false;
    }
    final root = _normalizeLibraryPath(outputPath);
    return _sameOrWithinPath(root, change.path) ||
        (change.destinationPath != null &&
            _sameOrWithinPath(root, change.destinationPath!));
  }

  bool _isRelevantLibraryFile(String path) {
    final lower = p.basename(path).toLowerCase();
    if (lower.endsWith('.thumb.jpg') ||
        lower.endsWith('.metadata.json') ||
        lower.endsWith('.frame.jpg') ||
        lower.endsWith('.tmp')) {
      return false;
    }
    final cachePath = timelineCache.filePath;
    if (cachePath != null && _samePath(path, cachePath)) {
      return false;
    }
    return scanner.supportsMediaPath(path) || scanner.isCoverPath(path);
  }

  bool _isKnownLibraryDirectory(String path) {
    bool contains(List<LibraryFolder> folders) {
      for (final folder in folders) {
        if (_samePath(folder.path, path) || contains(folder.children)) {
          return true;
        }
      }
      return false;
    }

    return _samePath(settings.outputPath, path) || contains(folderTree);
  }

  _LibraryDirectoryLocation? _libraryLocationForDirectory(
    String root,
    String directory,
  ) {
    if (!_sameOrWithinPath(root, directory)) {
      return null;
    }
    final relative = p.relative(directory, from: root);
    final parts = p.split(relative);
    if (relative == '.' || parts.length < 2 || parts.first == '..') {
      return null;
    }
    return _LibraryDirectoryLocation(
      platform: parts[0],
      game: parts[1],
      subAlbumPath: parts.length == 2 ? '' : p.joinAll(parts.skip(2)),
    );
  }

  bool _sameSource(MediaItem left, MediaItem right) {
    return left.sourceModifiedAt != null &&
        left.sourceModifiedAt == right.sourceModifiedAt &&
        left.sourceSize == right.sourceSize;
  }

  String _normalizeLibraryPath(String path) =>
      p.normalize(p.absolute(expandUserPath(path.trim())));

  String _pathKey(String path) {
    final normalized = _normalizeLibraryPath(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  bool _sameOrWithinPath(String parent, String child) {
    final parentKey = _pathKey(parent);
    final childKey = _pathKey(child);
    return parentKey == childKey || p.isWithin(parentKey, childKey);
  }

  Future<ImportResult> _collectProviderSafely(
    ScreenshotProvider provider,
  ) async {
    try {
      return await _collectProvider(provider);
    } catch (exception, stackTrace) {
      _logProviderFailure(provider, exception, stackTrace);
      return ImportResult.warning(
        provider.name,
        '${provider.name} could not be processed: ${_providerFailureSummary(exception)}',
      );
    }
  }

  void _logProviderFailure(
    ScreenshotProvider provider,
    Object exception,
    StackTrace stackTrace,
  ) {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    debugPrint(
      '[Gaming Memories][$timestamp] Provider "${provider.name}" failed.\n'
      'Error: ${_redactDiagnostic('$exception')}\n'
      'Stack trace:\n${_redactDiagnostic('$stackTrace')}',
    );
  }

  String _providerFailureSummary(Object exception) {
    final lines = _redactDiagnostic('$exception').split('\n');
    final firstLine = lines.first.trim();
    if (firstLine.isEmpty) {
      return 'Unexpected ${exception.runtimeType} failure. See the console log for details.';
    }
    const maximumLength = 240;
    final summary = firstLine.length <= maximumLength
        ? firstLine
        : '${firstLine.substring(0, maximumLength - 1)}…';
    return '$summary See the console log for details.';
  }

  String _redactDiagnostic(String value) {
    var redacted = value;
    final apiKey = settings.steam.apiKey.trim();
    if (apiKey.isNotEmpty) {
      redacted = redacted.replaceAll(apiKey, '<REDACTED>');
    }
    return redacted.replaceAllMapped(
      RegExp(r'([?&](?:key|api[_-]?key)=)[^&\s]+', caseSensitive: false),
      (match) => '${match.group(1)}<REDACTED>',
    );
  }

  Future<ImportResult> _collectProvider(ScreenshotProvider provider) async {
    if (!usesPersistentFolderAccess ||
        provider is! FolderBackedScreenshotProvider) {
      return provider.collect(settings, onProgress: _providerProgress);
    }

    final requirement = provider.folderRequirement(settings);
    if (requirement == null) {
      return provider.collect(settings, onProgress: _providerProgress);
    }
    final grant = settings.folderGrants[requirement.id];
    if (grant == null ||
        grant.bookmark.isEmpty ||
        !_samePath(grant.path, requirement.path)) {
      _folderAuthorizations[requirement.id] =
          FolderAuthorization.needsAuthorization(path: requirement.path);
      return ImportResult.warning(
        provider.name,
        '${provider.name} was skipped because its screenshot folder needs access. Open Settings and allow access.',
      );
    }

    FolderAccessLease? lease;
    try {
      lease = await folderAccess.activate(grant);
      if (requirement.automatic &&
          !_samePath(lease.grant.path, requirement.path)) {
        _folderAuthorizations[requirement.id] =
            FolderAuthorization.needsAuthorization(path: requirement.path);
        return ImportResult.warning(
          provider.name,
          '${provider.name} was skipped because its automatically discovered folder needs access again.',
        );
      }
      await _ensureReadableDirectory(lease.grant.path);
      _folderAuthorizations[requirement.id] = FolderAuthorization(
        FolderAuthorizationStatus.ready,
        path: lease.grant.path,
      );
      if (_grantChanged(grant, lease.grant)) {
        var next = _withGrant(settings, requirement.id, lease.grant);
        if (!requirement.automatic) {
          next = provider.withFolderPath(next, lease.grant.path);
        }
        await configStore.save(next);
        settings = next;
      }
      final runtimeSettings = provider.withFolderPath(
        settings,
        lease.grant.path,
      );
      return await provider.collect(
        runtimeSettings,
        onProgress: _providerProgress,
      );
    } on FolderAccessException catch (exception, stackTrace) {
      _logProviderFailure(provider, exception, stackTrace);
      _folderAuthorizations[requirement.id] =
          FolderAuthorization.needsAuthorization(path: grant.path);
      return ImportResult.warning(
        provider.name,
        '${provider.name} was skipped because folder access could not be restored. Open Settings and allow access again.',
      );
    } on FileSystemException catch (exception, stackTrace) {
      _logProviderFailure(provider, exception, stackTrace);
      _folderAuthorizations[requirement.id] = FolderAuthorization(
        FolderAuthorizationStatus.unavailable,
        path: grant.path,
      );
      return ImportResult.warning(
        provider.name,
        '${provider.name} was skipped because its screenshot folder is unavailable.',
      );
    } finally {
      if (lease != null) {
        await folderAccess.release(lease);
      }
    }
  }

  void _providerProgress(ProviderProgress progress) {
    _setProgress(progress.message, value: progress.value);
  }

  Future<void> _ensureReadableDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw FileSystemException('The selected folder does not exist.', path);
    }
    await directory.list(followLinks: false).take(1).toList();
  }

  Future<void> _ensureWritableDirectory(String path) async {
    await _ensureReadableDirectory(path);
    final probe = File(
      p.join(
        path,
        '.gaming-memories-access-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await probe.writeAsBytes(const [], flush: true);
    } on FileSystemException {
      throw FileSystemException(
        'The selected library folder is not writable.',
        path,
      );
    } finally {
      if (await probe.exists()) {
        await probe.delete();
      }
    }
  }

  void _refreshAuthorizationStates() {
    if (!usesPersistentFolderAccess) {
      return;
    }
    final outputPath = settings.outputPath.trim();
    if (outputPath.isEmpty) {
      _folderAuthorizations[FolderGrantIds.library] =
          const FolderAuthorization.notRequired();
    } else if (_libraryLease == null ||
        !_samePath(_libraryLease!.grant.path, outputPath)) {
      _folderAuthorizations[FolderGrantIds.library] =
          FolderAuthorization.needsAuthorization(path: outputPath);
    }

    for (final provider
        in providers.whereType<FolderBackedScreenshotProvider>()) {
      final requirement = provider.folderRequirement(settings);
      if (requirement == null) {
        _folderAuthorizations[provider.folderGrantId] =
            const FolderAuthorization.notRequired();
        continue;
      }
      final grant = settings.folderGrants[requirement.id];
      if (grant == null || !_samePath(grant.path, requirement.path)) {
        _folderAuthorizations[requirement.id] =
            FolderAuthorization.needsAuthorization(path: requirement.path);
      }
    }
  }

  AppSettings _withGrant(AppSettings value, String id, FolderGrant grant) {
    return value.copyWith(
      folderGrants: Map.unmodifiable({...value.folderGrants, id: grant}),
    );
  }

  bool _grantChanged(FolderGrant left, FolderGrant right) {
    return left.platform != right.platform ||
        left.path != right.path ||
        left.access != right.access ||
        left.bookmark != right.bookmark;
  }

  bool _samePath(String left, String right, {bool allowEmpty = false}) {
    final leftValue = left.trim();
    final rightValue = right.trim();
    if (allowEmpty && leftValue.isEmpty && rightValue.isEmpty) {
      return true;
    }
    if (leftValue.isEmpty || rightValue.isEmpty) {
      return false;
    }
    final normalizedLeft = p.normalize(p.absolute(expandUserPath(leftValue)));
    final normalizedRight = p.normalize(p.absolute(expandUserPath(rightValue)));
    return Platform.isWindows
        ? normalizedLeft.toLowerCase() == normalizedRight.toLowerCase()
        : normalizedLeft == normalizedRight;
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : expandUserPath(trimmed);
  }

  Future<void> _releaseLibraryLease() async {
    final lease = _libraryLease;
    _libraryLease = null;
    if (lease != null) {
      await folderAccess.release(lease);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    isBusy = true;
    message = null;
    error = null;
    notificationKind = null;
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
      _scheduleLibraryChangeFlush();
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
    notificationKind = null;

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
    notificationKind = NotificationKind.success;
    _recordNotification(value, NotificationKind.success);
  }

  void _setWarning(String value) {
    message = value;
    error = null;
    notificationKind = NotificationKind.warning;
    _recordNotification(value, NotificationKind.warning);
  }

  void _setError(String value) {
    error = value;
    message = null;
    notificationKind = NotificationKind.error;
    _recordNotification(value, NotificationKind.error);
  }

  void _recordNotification(String value, NotificationKind kind) {
    notificationRevision++;
    _notifications.add(
      AppNotification(
        revision: notificationRevision,
        message: value,
        kind: kind,
      ),
    );
    if (_notifications.length > 50) {
      _notifications.removeAt(0);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _libraryChangeTimer?.cancel();
    _libraryWatchRecoveryTimer?.cancel();
    unawaited(_libraryWatchSubscription?.cancel());
    unawaited(folderAccess.dispose());
    super.dispose();
  }
}

class _ProviderValidation {
  const _ProviderValidation(this.settings, this.errors);

  final AppSettings settings;
  final Map<String, String> errors;

  List<String> get disabledProviders => errors.keys.toList(growable: false);
}

class _LibraryDirectoryLocation {
  const _LibraryDirectoryLocation({
    required this.platform,
    required this.game,
    required this.subAlbumPath,
  });

  final String platform;
  final String game;
  final String subAlbumPath;
}

class _FolderSpecification {
  const _FolderSpecification({
    required this.request,
    required this.selectedPath,
    this.expectedPath,
    this.pathMismatchMessage,
  });

  final FolderAccessRequest request;
  final String? expectedPath;
  final String? pathMismatchMessage;
  final String Function(AppSettings settings) selectedPath;
}
