import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../models/library.dart';
import '../services/app_log.dart';
import '../services/battle_net_games.dart';
import '../services/config_store.dart';
import '../services/folder_access_service.dart';
import '../services/library_scanner.dart';
import '../services/library_watcher.dart';
import '../services/screenshot_action_service.dart';
import '../services/source_paths.dart';
import '../services/timeline_cache.dart';
import '../services/user_facing_error.dart';
import '../sources/battle_net_source.dart';
import '../sources/screenshot_source.dart';

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
  battleNetGameCustom,
  battleNetGameAutomatic,
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
  const AutomaticFolderCandidate({
    required this.name,
    required this.path,
    required this.grantId,
    this.description,
  });

  final String name;
  final String path;

  /// The grant this folder is stored under. Sources that span several
  /// folders give each one its own id.
  final String grantId;

  /// What this folder holds, when the source says.
  final String? description;
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

/// What the library is doing, for the sidebar status panel.
enum LibraryActivityKind {
  /// Nothing is running and the library is usable.
  idle,

  /// The library folder is missing or unreadable, so nothing can run.
  attention,

  /// The watcher saw changes that are waiting for a running operation.
  detected,

  /// Watched changes are being folded into the timeline.
  updating,

  /// The whole library is being rescanned.
  refreshing,
}

/// A snapshot of the library's current state, rendered as a status panel.
class LibraryActivity {
  const LibraryActivity({
    required this.kind,
    required this.title,
    this.detail,
    this.progress,
  });

  final LibraryActivityKind kind;
  final String title;
  final String? detail;

  /// The completion of a running operation, when it reports one. A running
  /// activity without a value is indeterminate.
  final double? progress;

  bool get isRunning =>
      kind == LibraryActivityKind.updating ||
      kind == LibraryActivityKind.refreshing;
}

/// The source scan action's current presentation in the sidebar.
class LibraryScanActivity {
  const LibraryScanActivity({
    required this.isRunning,
    required this.title,
    required this.detail,
    this.progress,
  });

  const LibraryScanActivity.idle()
    : isRunning = false,
      title = 'Scan for captures',
      detail = 'Collect from enabled sources',
      progress = null;

  final bool isRunning;
  final String title;
  final String detail;

  /// The completion of the active source's work. Null means indeterminate.
  final double? progress;
}

/// What a batch of watched library changes did to the timeline.
class LibraryChangeSummary {
  const LibraryChangeSummary({
    required this.added,
    required this.removed,
    required this.updated,
  });

  final int added;
  final int removed;
  final int updated;

  bool get isEmpty => added == 0 && removed == 0 && updated == 0;

  /// A compact line such as `3 added · 1 removed`.
  String describe() {
    final parts = <String>[
      if (added > 0) '$added added',
      if (removed > 0) '$removed removed',
      if (updated > 0) '$updated updated',
    ];
    return parts.join(' · ');
  }
}

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.configStore,
    required this.scanner,
    required this.sources,
    this.timelineCache = const TimelineCache.disabled(),
    this.libraryWatcher = const NativeLibraryWatcher(),
    this.folderAccess = const PathFolderAccessService(),
    this.sourcePaths = const SourcePathResolver(),
    this.screenshotActions = const NativeScreenshotActionService(),
    this.log = const SilentAppLog(),
  }) {
    // The log does not know what a secret looks like; this does.
    log.redact = _redactDiagnostic;
  }

  final ConfigStore configStore;
  final LibraryScanner scanner;
  final List<ScreenshotSource> sources;
  final TimelineCache timelineCache;
  final LibraryWatcher libraryWatcher;
  final FolderAccessService folderAccess;
  final SourcePathResolver sourcePaths;
  final ScreenshotActionService screenshotActions;
  final AppLog log;

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
  Map<String, String> _sourceValidationErrors = const {};
  final Map<String, FolderAuthorization> _folderAuthorizations = {};
  FolderAccessLease? _libraryLease;
  Future<void>? _timelineRefresh;
  String? _timelineRefreshPath;
  StreamSubscription<LibraryChange>? _libraryWatchSubscription;
  String? _watchedLibraryPath;
  int _libraryWatchGeneration = 0;
  final ListQueue<_QueuedLibraryChange> _pendingLibraryChanges = ListQueue();
  Timer? _libraryWatchRecoveryTimer;
  Timer? _libraryChangeSummaryTimer;
  Future<void>? _libraryChangeRefresh;
  int _applyingLibraryChanges = 0;
  bool _timelineCacheDirty = false;
  LibraryChangeSummary? _lastLibraryChange;
  int _folderRequest = 0;

  /// What the watcher queue has done to the visible listing since it was last
  /// opened. A folder load and its preview pass publish the snapshot they
  /// started from, so these are replayed over it to keep live arrivals.
  final Map<String, MediaItem> _liveListingMedia = {};
  final Map<String, LibraryFolder> _liveListingFolders = {};
  final List<String> _liveListingRemovals = [];
  bool _disposed = false;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  /// Watched changes that are waiting for a running operation to finish.
  int get pendingLibraryChangeCount =>
      _pendingLibraryChanges.length + _applyingLibraryChanges;

  /// What the last batch of watched changes did, until it expires.
  LibraryChangeSummary? get lastLibraryChange => _lastLibraryChange;

  /// What the source scan action is doing right now.
  LibraryScanActivity get scanActivity {
    if (!isBusy) {
      return const LibraryScanActivity.idle();
    }
    final percent = progressValue == null
        ? null
        : (progressValue! * 100).round();
    return LibraryScanActivity(
      isRunning: true,
      title: percent == null ? 'Scanning…' : 'Scanning · $percent%',
      detail: progressMessage ?? 'Checking enabled sources…',
      progress: progressValue,
    );
  }

  /// What the library is doing right now, most urgent state first.
  LibraryActivity get libraryActivity {
    if (isInitializing) {
      return const LibraryActivity(
        kind: LibraryActivityKind.idle,
        title: 'Starting…',
      );
    }
    if (isTimelineRefreshing) {
      // The refresh message only repeats the title, so the bar carries it.
      return LibraryActivity(
        kind: LibraryActivityKind.refreshing,
        title: 'Refreshing…',
        progress: progressValue,
      );
    }
    if (_applyingLibraryChanges > 0) {
      return LibraryActivity(
        kind: LibraryActivityKind.updating,
        title: 'Updating library…',
        detail: _changeCount(_applyingLibraryChanges),
      );
    }
    if (_pendingLibraryChanges.isNotEmpty) {
      return LibraryActivity(
        kind: LibraryActivityKind.detected,
        title: 'Changes detected',
        detail: _changeCount(_pendingLibraryChanges.length),
      );
    }
    if (settings.outputPath.trim().isEmpty) {
      return const LibraryActivity(
        kind: LibraryActivityKind.attention,
        title: 'No library folder',
        detail: 'Choose one in Settings',
      );
    }
    if (libraryNeedsAuthorization) {
      return const LibraryActivity(
        kind: LibraryActivityKind.attention,
        title: 'Access needed',
        detail: 'Allow access in Settings',
      );
    }
    if (_lastLibraryChange case final summary?) {
      return LibraryActivity(
        kind: LibraryActivityKind.idle,
        title: 'Library updated',
        detail: summary.describe(),
      );
    }
    final count = timelineMedia.length;
    return LibraryActivity(
      kind: LibraryActivityKind.idle,
      title: 'Up to date',
      detail: count == 1 ? '1 capture' : '$count captures',
    );
  }

  String _changeCount(int count) => count == 1 ? '1 change' : '$count changes';

  /// The Battle.net source, when it is configured. The settings page asks it
  /// which games it found; nothing else needs to know a source's type.
  BattleNetSource? get battleNetSource =>
      sources.whereType<BattleNetSource>().firstOrNull;

  BattleNetLocator get _battleNetLocator =>
      battleNetSource?.locator ?? const BattleNetLocator();

  /// Every Battle.net game with its resolved folder, for the settings rows.
  List<BattleNetGameFolder> battleNetGameFolders(AppSettings value) =>
      battleNetSource?.gameFolders(value) ?? const [];

  Map<String, String> get sourceValidationErrors => _sourceValidationErrors;

  String? sourceValidationError(String sourceName) =>
      _sourceValidationErrors[sourceName];

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
      SettingsFolderTarget.steamAutomatic =>
        sourcePaths.steamUserdataCandidates(),
      SettingsFolderTarget.hytaleAutomatic => [
        ?sourcePaths.hytaleScreenshots(),
      ],
      SettingsFolderTarget.minecraftAutomatic =>
        sourcePaths.minecraftScreenshots(),
      _ => const <String>[],
    };
    final grantId = _folderTargetGrantId(target);
    return paths
        .map(
          (path) => AutomaticFolderCandidate(
            name: p.basename(p.normalize(path)),
            path: path,
            grantId: grantId,
          ),
        )
        .toList(growable: false);
  }

  String _folderTargetGrantId(SettingsFolderTarget target) {
    return switch (target) {
      SettingsFolderTarget.library => FolderGrantIds.library,
      SettingsFolderTarget.battleNetGameCustom ||
      SettingsFolderTarget.battleNetGameAutomatic => FolderGrantIds.battleNet,
      SettingsFolderTarget.guildWars2Custom => FolderGrantIds.guildWars2,
      SettingsFolderTarget.hytaleCustom ||
      SettingsFolderTarget.hytaleAutomatic => FolderGrantIds.hytale,
      SettingsFolderTarget.minecraftCustom ||
      SettingsFolderTarget.minecraftAutomatic => FolderGrantIds.minecraft,
      SettingsFolderTarget.nintendoSwitch2Custom =>
        FolderGrantIds.nintendoSwitch2,
      SettingsFolderTarget.playStation4Custom => FolderGrantIds.playStation4,
      SettingsFolderTarget.playStation5Custom => FolderGrantIds.playStation5,
      SettingsFolderTarget.steamCustom ||
      SettingsFolderTarget.steamAutomatic => FolderGrantIds.steam,
    };
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
    // This load reads the folder as it is now, so only what lands from here on
    // has to be replayed over it.
    _clearLiveListingChanges();
    isViewLoading = true;
    notifyListeners();
    try {
      final listing = await scanner.folderContents(
        settings.outputPath,
        platform,
        game,
        subAlbumPath: subAlbumPath,
        onUpdate: (listing) => _publishLoadedListing(request, listing),
      );
      if (request == _folderRequest && !_disposed) {
        _publishLoadedListing(request, listing);
        await _prepareSelectedFolder(request, listing);
      }
    } catch (exception, stackTrace) {
      if (request == _folderRequest && !_disposed) {
        _fail('open this folder', exception, stackTrace, category: 'library');
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
        onUpdate: (prepared) => _publishLoadedListing(request, prepared),
      );
    } catch (exception, stackTrace) {
      if (request == _folderRequest && !_disposed) {
        _fail('prepare previews', exception, stackTrace, category: 'library');
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
        changed = await _restoreSourceGrants() || changed;
        final validation = await _validateEnabledSources(settings);
        settings = validation.settings;
        _sourceValidationErrors = Map.unmodifiable(validation.errors);
        changed = validation.disabledSources.isNotEmpty || changed;
        if (changed) {
          await configStore.save(settings);
        }
        _showSourceValidationErrors(validation.errors);
      } else {
        final validation = await _validateEnabledSources(settings);
        settings = validation.settings;
        _sourceValidationErrors = Map.unmodifiable(validation.errors);
        if (validation.disabledSources.isNotEmpty) {
          await configStore.save(settings);
        }
        _showSourceValidationErrors(validation.errors);
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
    } catch (exception, stackTrace) {
      _fail('load the library', exception, stackTrace, category: 'library');
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

  Future<bool> _restoreSourceGrants() async {
    var changed = false;
    for (final source in sources.whereType<FolderBackedScreenshotSource>()) {
      final requirements = source.folderRequirements(settings);
      if (requirements.isEmpty) {
        _folderAuthorizations[source.folderGrantId] =
            const FolderAuthorization.notRequired();
        continue;
      }
      for (final requirement in requirements) {
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
              next = source.withFolderPath(next, lease.grant.path);
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
    } catch (exception, stackTrace) {
      if (!_disposed) {
        _fail('load sub-albums', exception, stackTrace, category: 'library');
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
    _clearLiveListingChanges();
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
    _clearLiveListingChanges();
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
    _clearLiveListingChanges();
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
    Map<String, String> sourceErrors = const {},
  }) async {
    try {
      final validation = await _validateEnabledSources(
        next,
        knownErrors: sourceErrors,
      );
      final validated = validation.settings;
      _sourceValidationErrors = Map.unmodifiable(validation.errors);
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
        if (validation.disabledSources.isEmpty) {
          _setMessage('Settings saved.');
        } else {
          _setError(_sourceValidationMessage(validation.errors));
        }
      }
      notifyListeners();
      if (outputChanged && !libraryNeedsAuthorization) {
        await _loadLibrarySnapshot();
        unawaited(_refreshTimeline(showResult: false));
      }
      return true;
    } catch (exception, stackTrace) {
      _fail('save your settings', exception, stackTrace, category: 'settings');
      notifyListeners();
      return false;
    }
  }

  Future<String?> sourceConfigurationError(
    String sourceName,
    AppSettings value,
  ) async {
    for (final source in sources) {
      if (source.name == sourceName) {
        return _sourceConfigurationError(source, value);
      }
    }
    return null;
  }

  Future<_SourceValidation> _validateEnabledSources(
    AppSettings candidate, {
    Map<String, String> knownErrors = const {},
  }) async {
    var validated = candidate;
    final errors = <String, String>{};
    for (final source in sources) {
      if (!source.isEnabled(validated) ||
          !_supportsSourceSettings(source.name)) {
        continue;
      }
      final error =
          knownErrors[source.name] ??
          await _sourceConfigurationError(source, validated);
      if (error == null) {
        continue;
      }
      validated = _withSourceEnabled(validated, source.name, false);
      errors[source.name] = error;
    }
    return _SourceValidation(validated, errors);
  }

  Future<String?> _sourceConfigurationError(
    ScreenshotSource source,
    AppSettings candidate,
  ) async {
    if (source case FolderBackedScreenshotSource folderSource) {
      final requirements = folderSource.folderRequirements(candidate);
      if (requirements.isEmpty) {
        if (source.name == 'Nintendo Switch 2' && Platform.isLinux) {
          return null;
        }
        return 'No supported ${source.name} folder is configured.';
      }
      if (usesPersistentFolderAccess) {
        // One granted folder is enough to run: a source that spans several
        // folders imports whichever of them it can reach.
        final anyReady = requirements.any((requirement) {
          final authorization = folderAuthorization(requirement.id);
          return authorization.isReady &&
              _samePath(authorization.path ?? '', requirement.path);
        });
        if (!anyReady) {
          return 'Folder access is required for ${source.name}.';
        }
      } else {
        final existing = <bool>[
          for (final requirement in requirements)
            await _sourceFolderExists(source, requirement),
        ];
        if (!existing.contains(true)) {
          return '${source.name} folder does not exist.';
        }
      }
    }
    if (source is SourceConfigurationValidator) {
      return (source as SourceConfigurationValidator).configurationError(
        candidate,
      );
    }
    return null;
  }

  Future<bool> _sourceFolderExists(
    ScreenshotSource source,
    SourceFolderRequirement requirement,
  ) async {
    if (await Directory(requirement.path).exists()) {
      return true;
    }
    if (!requirement.automatic) {
      return false;
    }
    final candidates = switch (source.name) {
      'Hytale' => [sourcePaths.hytaleScreenshots()],
      'Minecraft' => sourcePaths.minecraftScreenshots(),
      'Steam' => sourcePaths.steamUserdataCandidates(),
      _ => <String?>[],
    };
    for (final path in candidates.whereType<String>()) {
      if (await Directory(path).exists()) {
        return true;
      }
    }
    return false;
  }

  AppSettings _withSourceEnabled(
    AppSettings value,
    String sourceName,
    bool enabled,
  ) => switch (sourceName) {
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

  bool _supportsSourceSettings(String sourceName) => switch (sourceName) {
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

  void _showSourceValidationErrors(Map<String, String> errors) {
    if (errors.isNotEmpty) {
      _setError(_sourceValidationMessage(errors));
    }
  }

  String _sourceValidationMessage(Map<String, String> errors) {
    if (errors.length == 1) {
      final error = errors.entries.single;
      return '${error.key} was disabled: ${error.value}';
    }
    final details = errors.entries
        .map((error) => '${error.key}: ${error.value}')
        .join(' ');
    return 'Invalid sources were disabled. $details';
  }

  Future<FolderChoiceResult> chooseFolder(
    SettingsFolderTarget target, {
    String? initialPath,
    String? gameId,
  }) async {
    final specification = _folderSpecification(target, initialPath, gameId);
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

      var next = _settingsWithFolder(target, lease.grant.path, gameId: gameId);
      if (usesPersistentFolderAccess) {
        next = _withGrant(next, specification.request.id, lease.grant);
      }
      _folderAuthorizations[specification.request.id] = FolderAuthorization(
        FolderAuthorizationStatus.ready,
        path: lease.grant.path,
      );
      final validation = await _validateEnabledSources(next);
      next = validation.settings;
      _sourceValidationErrors = Map.unmodifiable(validation.errors);
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
      if (validation.disabledSources.isEmpty) {
        _setMessage('Settings saved.');
      } else {
        _setError(_sourceValidationMessage(validation.errors));
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
    } catch (exception, stackTrace) {
      log.error(
        'Could not save folder access.',
        category: 'folder-access',
        error: exception,
        stackTrace: stackTrace,
      );
      return FolderChoiceResult.failure(
        describeFailure(exception, action: 'save folder access'),
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
    String? gameId,
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
      case SettingsFolderTarget.battleNetGameCustom:
        final game = gameId == null ? null : battleNetGameById(gameId);
        if (game == null) {
          return null;
        }
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: BattleNetSource.grantIdForGame(game.id),
            title: 'Choose the ${game.name} screenshot folder',
            access: FolderGrantAccess.readOnly,
            initialPath:
                _nonEmpty(initialPath) ??
                _nonEmpty(settings.battleNet.game(game.id).sourcePath),
          ),
          selectedPath: (settings) =>
              settings.battleNet.game(game.id).sourcePath,
        );
      case SettingsFolderTarget.battleNetGameAutomatic:
        final game = gameId == null ? null : battleNetGameById(gameId);
        if (game == null) {
          return null;
        }
        final candidate = _battleNetLocator.resolve(game).path;
        if (candidate == null) {
          return null;
        }
        return _FolderSpecification(
          request: FolderAccessRequest(
            id: BattleNetSource.grantIdForGame(game.id),
            title: 'Allow access to ${game.name} screenshots',
            access: FolderGrantAccess.readOnly,
            initialPath: candidate,
            suggestedPath: candidate,
            message:
                'Click Allow Access to grant Gaming Memories access to the ${game.name} screenshot folder.',
          ),
          expectedPath: candidate,
          pathMismatchMessage:
              'Choose the ${game.name} folder shown by Gaming Memories.',
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

  AppSettings _settingsWithFolder(
    SettingsFolderTarget target,
    String path, {
    String? gameId,
  }) {
    return switch (target) {
      SettingsFolderTarget.library => settings.copyWith(outputPath: path),
      SettingsFolderTarget.battleNetGameCustom =>
        gameId == null
            ? settings
            : settings.copyWith(
                battleNet: settings.battleNet.withGame(
                  gameId,
                  settings.battleNet
                      .game(gameId)
                      .copyWith(
                        enabled: true,
                        useCustomPath: true,
                        sourcePath: path,
                      ),
                ),
              ),
      SettingsFolderTarget.battleNetGameAutomatic => settings,
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
      final enabledSources = sources
          .where((source) => source.isEnabled(settings))
          .toList(growable: false);
      for (final source in enabledSources) {
        final usesLibraryFolder = source is FolderBackedScreenshotSource;
        if (usesLibraryFolder && settings.outputPath.trim().isEmpty) {
          results.add(
            ImportResult.warning(
              source.name,
              '${source.name} was skipped because no library folder is selected.',
            ),
          );
          continue;
        }
        if (usesLibraryFolder && libraryNeedsAuthorization) {
          results.add(
            ImportResult.warning(
              source.name,
              '${source.name} was skipped because the library folder needs access.',
            ),
          );
          continue;
        }

        _setProgress('Preparing ${source.name}…');
        results.add(await _collectSourceSafely(source));
      }
      final imported = results.fold(0, (sum, result) => sum + result.imported);
      final skipped = results.fold(0, (sum, result) => sum + result.skipped);
      final warnings = results
          .map((result) => result.warning)
          .whereType<String>()
          .toList(growable: false);
      if (results.isEmpty) {
        _setMessage('Enable a source in Settings first.');
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
    _clearLiveListingChanges();
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
      _timelineCacheDirty = false;
      folderTree = await scanner.folderTree(outputPath);
      if (showResult) {
        _setMessage('Timeline refreshed.');
      }
    } catch (exception, stackTrace) {
      if (!_disposed) {
        _fail(
          'refresh the timeline',
          exception,
          stackTrace,
          category: 'library',
        );
      }
    } finally {
      if (!_disposed) {
        isTimelineRefreshing = false;
        progressMessage = null;
        progressValue = null;
        notifyListeners();
        _startLibraryChangeQueue();
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
    log.warning(
      'The library watcher failed.',
      category: 'watcher',
      error: error,
      stackTrace: stackTrace,
    );
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
    _pendingLibraryChanges.add(
      _QueuedLibraryChange(_libraryWatchGeneration, normalized),
    );
    notifyListeners();
    _startLibraryChangeQueue();
  }

  void _startLibraryChangeQueue() {
    if (_disposed ||
        isTimelineRefreshing ||
        _pendingLibraryChanges.isEmpty ||
        _libraryChangeRefresh != null) {
      return;
    }
    final operation = _drainLibraryChangeQueue();
    _libraryChangeRefresh = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_libraryChangeRefresh, operation)) {
          _libraryChangeRefresh = null;
        }
        _startLibraryChangeQueue();
      }),
    );
  }

  Future<void> _drainLibraryChangeQueue() async {
    _applyingLibraryChanges = 1;
    if (!_disposed) {
      notifyListeners();
    }
    try {
      while (!_disposed &&
          !isTimelineRefreshing &&
          _pendingLibraryChanges.isNotEmpty) {
        final queued = _pendingLibraryChanges.removeFirst();
        if (queued.generation != _libraryWatchGeneration) {
          continue;
        }
        try {
          await _applyLibraryChange(queued);
        } catch (error, stackTrace) {
          log.warning(
            'Could not apply a library change.',
            category: 'watcher',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      if (!_disposed && !isTimelineRefreshing && _timelineCacheDirty) {
        _timelineCacheDirty = false;
        try {
          await timelineCache.save(
            settings.outputPath,
            List<MediaItem>.of(timelineMedia),
          );
        } catch (error, stackTrace) {
          _timelineCacheDirty = true;
          log.warning(
            'Could not save live library changes.',
            category: 'watcher',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } finally {
      _applyingLibraryChanges = 0;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _applyLibraryChange(_QueuedLibraryChange queued) async {
    final outputPath = settings.outputPath;
    if (!_queuedChangeIsCurrent(queued, outputPath)) {
      return;
    }
    final root = _normalizeLibraryPath(outputPath);
    final change = queued.change;
    final source = change.path;
    final sourceIsDirectory =
        change.isDirectory || _isKnownLibraryDirectory(source);
    var added = 0;
    var removed = 0;
    var updated = 0;
    var timelineChanged = false;

    void publish() {
      if (_queuedChangeIsCurrent(queued, outputPath)) {
        notifyListeners();
      }
    }

    void removePath(String path, {required bool isDirectory}) {
      final removedCount = _removeTimelinePath(path, recursive: isDirectory);
      removed += removedCount;
      timelineChanged = timelineChanged || removedCount > 0;
      var presentationChanged = _removeVisiblePath(path);
      if (isDirectory) {
        presentationChanged =
            _removeLibraryFolder(root, path) || presentationChanged;
      } else if (scanner.isCoverPath(path)) {
        presentationChanged =
            _setGameCover(root, path, present: false) || presentationChanged;
      }
      if (removedCount > 0 || presentationChanged) {
        publish();
      }
    }

    Future<void> addPath(
      String path, {
      required bool isDirectory,
      required bool scanDirectory,
    }) async {
      if (isDirectory) {
        final treeChanged = _upsertLibraryFolder(root, path);
        final listingChanged = _upsertVisibleFolder(root, path);
        if (treeChanged || listingChanged) {
          // Folder navigation is independent of media preparation. Publish it
          // before a potentially slow subtree scan starts.
          publish();
        }
        if (!scanDirectory) {
          return;
        }
        final location = _libraryLocationForDirectory(root, path);
        if (location == null) {
          return;
        }
        final media = await scanner.mediaTree(
          outputPath,
          location.platform,
          location.game,
          subAlbumPath: location.subAlbumPath,
        );
        if (!_queuedChangeIsCurrent(queued, outputPath)) {
          return;
        }
        for (final item in media) {
          switch (_upsertTimelineItem(item)) {
            case _MediaMutation.added:
              added++;
              timelineChanged = true;
              break;
            case _MediaMutation.updated:
              updated++;
              timelineChanged = true;
              break;
            case _MediaMutation.none:
              break;
          }
          _upsertVisibleMedia(root, item);
        }
        if (media.isNotEmpty) {
          publish();
        }
        return;
      }

      if (_upsertLibraryFolder(root, p.dirname(path))) {
        // A file event can race ahead of its parent directory event.
        publish();
      }
      if (scanner.isCoverPath(path)) {
        if (_setGameCover(root, path, present: true)) {
          publish();
        }
        return;
      }
      if (!scanner.supportsMediaPath(path)) {
        return;
      }
      final item = await scanner.mediaItemAt(outputPath, path);
      if (item == null || !_queuedChangeIsCurrent(queued, outputPath)) {
        return;
      }
      switch (_upsertTimelineItem(item)) {
        case _MediaMutation.added:
          added++;
          timelineChanged = true;
          break;
        case _MediaMutation.updated:
          updated++;
          timelineChanged = true;
          break;
        case _MediaMutation.none:
          break;
      }
      final listingChanged = _upsertVisibleMedia(root, item);
      if (timelineChanged || listingChanged) {
        publish();
      }
    }

    if (change.kind == LibraryChangeKind.delete ||
        change.kind == LibraryChangeKind.move) {
      removePath(source, isDirectory: sourceIsDirectory);
    }
    if (change.kind == LibraryChangeKind.create ||
        change.kind == LibraryChangeKind.modify) {
      await addPath(
        source,
        isDirectory: sourceIsDirectory,
        scanDirectory: change.kind == LibraryChangeKind.create,
      );
    }
    final destination = change.destinationPath;
    if (change.kind == LibraryChangeKind.move && destination != null) {
      await addPath(
        destination,
        isDirectory: sourceIsDirectory,
        scanDirectory: sourceIsDirectory,
      );
    }

    if (!_queuedChangeIsCurrent(queued, outputPath)) {
      return;
    }
    if (added > 0 || removed > 0 || updated > 0) {
      _recordLibraryChangeSummary(
        LibraryChangeSummary(added: added, removed: removed, updated: updated),
      );
      publish();
    }
    _timelineCacheDirty = _timelineCacheDirty || timelineChanged;
  }

  bool _queuedChangeIsCurrent(_QueuedLibraryChange queued, String outputPath) {
    return !_disposed &&
        queued.generation == _libraryWatchGeneration &&
        _samePath(outputPath, settings.outputPath);
  }

  _MediaMutation _upsertTimelineItem(MediaItem item) {
    final key = _pathKey(item.path);
    final index = timelineMedia.indexWhere(
      (candidate) => _pathKey(candidate.path) == key,
    );
    if (index >= 0 && _sameSource(timelineMedia[index], item)) {
      return _MediaMutation.none;
    }
    final next = List<MediaItem>.of(timelineMedia);
    final mutation = index < 0 ? _MediaMutation.added : _MediaMutation.updated;
    if (index < 0) {
      next.add(item);
    } else {
      next[index] = item;
    }
    next.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    timelineMedia = next;
    library = const MediaLibrary.empty();
    if (selectedMedia case final selected?
        when _pathKey(selected.path) == key) {
      selectedMedia = item;
    }
    return mutation;
  }

  int _removeTimelinePath(String path, {required bool recursive}) {
    final next = List<MediaItem>.of(timelineMedia);
    final before = next.length;
    next.removeWhere(
      (media) => recursive
          ? _sameOrWithinPath(path, media.path)
          : _samePath(path, media.path),
    );
    final removed = before - next.length;
    if (removed == 0) {
      return 0;
    }
    timelineMedia = next;
    library = const MediaLibrary.empty();
    final selected = selectedMedia;
    if (selected != null &&
        (recursive
            ? _sameOrWithinPath(path, selected.path)
            : _samePath(path, selected.path))) {
      selectedMedia = null;
    }
    return removed;
  }

  bool _upsertLibraryFolder(String root, String path) {
    if (!_sameOrWithinPath(root, path) || _samePath(root, path)) {
      return false;
    }
    final parts = p.split(p.relative(path, from: root));
    if (parts.isEmpty || parts.first == '..') {
      return false;
    }
    final platforms = List<LibraryFolder>.of(folderTree);
    var platformIndex = platforms.indexWhere(
      (folder) => folder.name == parts[0],
    );
    var changed = false;
    if (platformIndex < 0) {
      platforms.add(
        LibraryFolder(name: parts[0], path: p.join(root, parts[0])),
      );
      platforms.sort((left, right) => left.name.compareTo(right.name));
      platformIndex = platforms.indexWhere((folder) => folder.name == parts[0]);
      changed = true;
    }
    if (parts.length == 1) {
      folderTree = platforms;
      return changed;
    }

    var platform = platforms[platformIndex];
    final games = List<LibraryFolder>.of(platform.children);
    var gameIndex = games.indexWhere((folder) => folder.name == parts[1]);
    if (gameIndex < 0) {
      games.add(
        LibraryFolder(
          name: parts[1],
          path: p.join(root, parts[0], parts[1]),
          relativePath: parts[1],
          childrenLoaded: false,
        ),
      );
      games.sort((left, right) => left.name.compareTo(right.name));
      gameIndex = games.indexWhere((folder) => folder.name == parts[1]);
      changed = true;
    }
    var game = games[gameIndex];
    if (parts.length > 2 && game.childrenLoaded) {
      final result = _upsertLoadedFolder(game, parts.sublist(2));
      game = result.folder;
      games[gameIndex] = game;
      changed = changed || result.changed;
    }
    platform = _copyLibraryFolder(platform, children: games);
    platforms[platformIndex] = platform;
    folderTree = platforms;
    return changed;
  }

  ({LibraryFolder folder, bool changed}) _upsertLoadedFolder(
    LibraryFolder game,
    List<String> segments,
  ) {
    LibraryFolder visit(LibraryFolder parent, int index) {
      final relative = p.joinAll(segments.take(index + 1));
      final children = List<LibraryFolder>.of(parent.children);
      var childIndex = children.indexWhere(
        (child) => child.name == segments[index],
      );
      if (childIndex < 0) {
        children.add(
          LibraryFolder(
            name: segments[index],
            path: p.join(game.path, relative),
            relativePath: relative,
          ),
        );
        children.sort((left, right) => left.name.compareTo(right.name));
        childIndex = children.indexWhere(
          (child) => child.name == segments[index],
        );
      }
      if (index + 1 < segments.length) {
        children[childIndex] = visit(children[childIndex], index + 1);
      }
      return _copyLibraryFolder(parent, children: children);
    }

    final existed = game.find(p.joinAll(segments)) != null;
    return (folder: visit(game, 0), changed: !existed);
  }

  bool _removeLibraryFolder(String root, String path) {
    if (!_sameOrWithinPath(root, path) || _samePath(root, path)) {
      return false;
    }
    final parts = p.split(p.relative(path, from: root));
    if (parts.isEmpty || parts.first == '..') {
      return false;
    }
    final platforms = List<LibraryFolder>.of(folderTree);
    final platformIndex = platforms.indexWhere(
      (folder) => folder.name == parts[0],
    );
    if (platformIndex < 0) {
      return false;
    }
    if (parts.length == 1) {
      platforms.removeAt(platformIndex);
      folderTree = platforms;
      return true;
    }
    final platform = platforms[platformIndex];
    final games = List<LibraryFolder>.of(platform.children);
    final gameIndex = games.indexWhere((folder) => folder.name == parts[1]);
    if (gameIndex < 0) {
      return false;
    }
    if (parts.length == 2) {
      games.removeAt(gameIndex);
      platforms[platformIndex] = _copyLibraryFolder(platform, children: games);
      folderTree = platforms;
      return true;
    }
    final result = _removeLoadedFolder(games[gameIndex], parts.sublist(2));
    if (!result.changed) {
      return false;
    }
    games[gameIndex] = result.folder;
    platforms[platformIndex] = _copyLibraryFolder(platform, children: games);
    folderTree = platforms;
    return true;
  }

  ({LibraryFolder folder, bool changed}) _removeLoadedFolder(
    LibraryFolder game,
    List<String> segments,
  ) {
    LibraryFolder visit(LibraryFolder parent, int index) {
      final children = List<LibraryFolder>.of(parent.children);
      final childIndex = children.indexWhere(
        (child) => child.name == segments[index],
      );
      if (childIndex < 0) {
        return parent;
      }
      if (index + 1 == segments.length) {
        children.removeAt(childIndex);
      } else {
        children[childIndex] = visit(children[childIndex], index + 1);
      }
      return _copyLibraryFolder(parent, children: children);
    }

    final existed = game.find(p.joinAll(segments)) != null;
    return (folder: existed ? visit(game, 0) : game, changed: existed);
  }

  bool _setGameCover(String root, String path, {required bool present}) {
    final relative = p.relative(path, from: root);
    final parts = p.split(relative);
    if (parts.length != 3 || parts.first == '..') {
      return false;
    }
    final platforms = List<LibraryFolder>.of(folderTree);
    final platformIndex = platforms.indexWhere(
      (folder) => folder.name == parts[0],
    );
    if (platformIndex < 0) {
      return false;
    }
    final platform = platforms[platformIndex];
    final games = List<LibraryFolder>.of(platform.children);
    final gameIndex = games.indexWhere((folder) => folder.name == parts[1]);
    if (gameIndex < 0) {
      return false;
    }
    final game = games[gameIndex];
    final nextCover = present ? path : null;
    if (game.coverPath == nextCover) {
      return false;
    }
    games[gameIndex] = _copyLibraryFolder(
      game,
      coverPath: nextCover,
      clearCover: !present,
    );
    platforms[platformIndex] = _copyLibraryFolder(platform, children: games);
    folderTree = platforms;
    return true;
  }

  LibraryFolder _copyLibraryFolder(
    LibraryFolder folder, {
    List<LibraryFolder>? children,
    String? coverPath,
    bool clearCover = false,
  }) {
    return LibraryFolder(
      name: folder.name,
      path: folder.path,
      relativePath: folder.relativePath,
      coverPath: clearCover ? null : coverPath ?? folder.coverPath,
      children: children ?? folder.children,
      childrenLoaded: folder.childrenLoaded,
    );
  }

  String? _visibleLibraryDirectory(String root) {
    if (view != LibraryView.album && view != LibraryView.subAlbum) {
      return null;
    }
    final platform = selectedPlatform;
    final game = selectedGame;
    if (platform == null || game == null) {
      return null;
    }
    return p.join(root, platform, game, selectedSubAlbumPath ?? '');
  }

  /// Publishes a listing a folder load produced, with the live edits that
  /// landed while it was running replayed over it.
  void _publishLoadedListing(int request, FolderListing listing) {
    if (request != _folderRequest || _disposed) {
      return;
    }
    folderListing = _withLiveListingChanges(listing);
    notifyListeners();
  }

  FolderListing _withLiveListingChanges(FolderListing listing) {
    if (_liveListingMedia.isEmpty &&
        _liveListingFolders.isEmpty &&
        _liveListingRemovals.isEmpty) {
      return listing;
    }

    final media = List<MediaItem>.of(listing.media);
    for (final item in _liveListingMedia.values) {
      final index = media.indexWhere(
        (candidate) => _samePath(candidate.path, item.path),
      );
      if (index < 0) {
        media.add(item);
      } else {
        media[index] = item;
      }
    }
    final folders = List<LibraryFolder>.of(listing.folders);
    for (final folder in _liveListingFolders.values) {
      if (!folders.any((candidate) => _samePath(candidate.path, folder.path))) {
        folders.add(folder);
      }
    }
    bool removed(String path) =>
        _liveListingRemovals.any((gone) => _sameOrWithinPath(gone, path));
    media
      ..removeWhere((item) => removed(item.path))
      ..sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    folders
      ..removeWhere((folder) => removed(folder.path))
      ..sort((left, right) => left.name.compareTo(right.name));
    return FolderListing(
      folders: List.unmodifiable(folders),
      media: List.unmodifiable(media),
    );
  }

  /// Starts the visible listing from scratch, so another album's live edits are
  /// never replayed over it.
  void _clearLiveListingChanges() {
    _liveListingMedia.clear();
    _liveListingFolders.clear();
    _liveListingRemovals.clear();
  }

  bool _upsertVisibleMedia(String root, MediaItem item) {
    final directory = _visibleLibraryDirectory(root);
    if (directory == null || !_samePath(directory, p.dirname(item.path))) {
      return false;
    }
    _liveListingMedia[_pathKey(item.path)] = item;
    _liveListingRemovals.removeWhere((gone) => _samePath(gone, item.path));
    final media = List<MediaItem>.of(folderListing.media);
    final index = media.indexWhere(
      (candidate) => _samePath(candidate.path, item.path),
    );
    if (index < 0) {
      media.add(item);
    } else {
      media[index] = item;
    }
    media.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    folderListing = FolderListing(folders: folderListing.folders, media: media);
    isViewLoading = false;
    return true;
  }

  bool _upsertVisibleFolder(String root, String path) {
    final directory = _visibleLibraryDirectory(root);
    if (directory == null || !_samePath(directory, p.dirname(path))) {
      return false;
    }
    final location = _libraryLocationForDirectory(root, path);
    if (location == null) {
      return false;
    }
    final folder = LibraryFolder(
      name: p.basename(path),
      path: path,
      relativePath: location.subAlbumPath,
    );
    _liveListingFolders[_pathKey(path)] = folder;
    _liveListingRemovals.removeWhere((gone) => _samePath(gone, path));
    if (folderListing.folders.any(
      (candidate) => _samePath(candidate.path, path),
    )) {
      return false;
    }
    final folders = List<LibraryFolder>.of(folderListing.folders)
      ..add(folder)
      ..sort((left, right) => left.name.compareTo(right.name));
    folderListing = FolderListing(folders: folders, media: folderListing.media);
    isViewLoading = false;
    return true;
  }

  bool _removeVisiblePath(String path) {
    _liveListingRemovals.add(path);
    _liveListingMedia.removeWhere(
      (_, item) => _sameOrWithinPath(path, item.path),
    );
    _liveListingFolders.removeWhere(
      (_, folder) => _sameOrWithinPath(path, folder.path),
    );
    final folders = folderListing.folders
        .where((folder) => !_sameOrWithinPath(path, folder.path))
        .toList(growable: false);
    final media = folderListing.media
        .where((item) => !_sameOrWithinPath(path, item.path))
        .toList(growable: false);
    if (folders.length == folderListing.folders.length &&
        media.length == folderListing.media.length) {
      return false;
    }
    folderListing = FolderListing(folders: folders, media: media);
    isViewLoading = false;
    return true;
  }

  /// Keeps what a batch of watched changes did on screen for a short while.
  void _recordLibraryChangeSummary(LibraryChangeSummary summary) {
    if (_disposed || summary.isEmpty) {
      return;
    }
    _lastLibraryChange = summary;
    _libraryChangeSummaryTimer?.cancel();
    _libraryChangeSummaryTimer = Timer(const Duration(seconds: 8), () {
      _libraryChangeSummaryTimer = null;
      if (_disposed) {
        return;
      }
      _lastLibraryChange = null;
      notifyListeners();
    });
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

  Future<ImportResult> _collectSourceSafely(ScreenshotSource source) async {
    try {
      return await _collectSource(source);
    } catch (exception, stackTrace) {
      _logSourceFailure(source, exception, stackTrace);
      return ImportResult.warning(
        source.name,
        describeFailure(exception, action: 'import from ${source.name}'),
      );
    }
  }

  void _logSourceFailure(
    ScreenshotSource source,
    Object exception,
    StackTrace stackTrace,
  ) {
    log.error(
      'Source "${source.name}" failed.',
      category: 'source',
      error: exception,
      stackTrace: stackTrace,
    );
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

  Future<ImportResult> _collectSource(ScreenshotSource source) async {
    if (!usesPersistentFolderAccess ||
        source is! FolderBackedScreenshotSource) {
      return source.collect(settings, onProgress: _sourceProgress);
    }

    final requirements = source.folderRequirements(settings);
    if (requirements.isEmpty) {
      return source.collect(settings, onProgress: _sourceProgress);
    }

    final leases = <FolderAccessLease>[];
    try {
      for (final requirement in requirements) {
        final lease = await _activateRequirement(source, requirement);
        if (lease != null) {
          leases.add(lease);
        }
      }
      if (leases.isEmpty) {
        return ImportResult.warning(
          source.name,
          '${source.name} was skipped because its screenshot folders need access. Open Settings and allow access.',
        );
      }
      // The primary requirement carries the custom root, which is the only
      // path a source stores. Automatic requirements span several folders
      // and must not be written back.
      final runtimeSettings = requirements.first.automatic
          ? settings
          : source.withFolderPath(settings, leases.first.grant.path);
      return await source.collect(runtimeSettings, onProgress: _sourceProgress);
    } finally {
      for (final lease in leases) {
        await folderAccess.release(lease);
      }
    }
  }

  /// Activates one required folder, recording its authorization state.
  ///
  /// Returns null when the folder is not usable, leaving the caller to decide
  /// whether the source can still run on the folders that are.
  Future<FolderAccessLease?> _activateRequirement(
    FolderBackedScreenshotSource source,
    SourceFolderRequirement requirement,
  ) async {
    final grant = settings.folderGrants[requirement.id];
    if (grant == null ||
        grant.bookmark.isEmpty ||
        !_samePath(grant.path, requirement.path)) {
      _folderAuthorizations[requirement.id] =
          FolderAuthorization.needsAuthorization(path: requirement.path);
      return null;
    }

    FolderAccessLease? lease;
    try {
      lease = await folderAccess.activate(grant);
      if (requirement.automatic &&
          !_samePath(lease.grant.path, requirement.path)) {
        _folderAuthorizations[requirement.id] =
            FolderAuthorization.needsAuthorization(path: requirement.path);
        await folderAccess.release(lease);
        return null;
      }
      await _ensureReadableDirectory(lease.grant.path);
      _folderAuthorizations[requirement.id] = FolderAuthorization(
        FolderAuthorizationStatus.ready,
        path: lease.grant.path,
      );
      if (_grantChanged(grant, lease.grant)) {
        var next = _withGrant(settings, requirement.id, lease.grant);
        if (!requirement.automatic) {
          next = source.withFolderPath(next, lease.grant.path);
        }
        await configStore.save(next);
        settings = next;
      }
      return lease;
    } on FolderAccessException catch (exception, stackTrace) {
      _logSourceFailure(source, exception, stackTrace);
      _folderAuthorizations[requirement.id] =
          FolderAuthorization.needsAuthorization(path: grant.path);
    } on FileSystemException catch (exception, stackTrace) {
      _logSourceFailure(source, exception, stackTrace);
      _folderAuthorizations[requirement.id] = FolderAuthorization(
        FolderAuthorizationStatus.unavailable,
        path: grant.path,
      );
    }
    if (lease != null) {
      await folderAccess.release(lease);
    }
    return null;
  }

  void _sourceProgress(SourceProgress progress) {
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

    for (final source in sources.whereType<FolderBackedScreenshotSource>()) {
      final requirements = source.folderRequirements(settings);
      if (requirements.isEmpty) {
        _folderAuthorizations[source.folderGrantId] =
            const FolderAuthorization.notRequired();
        continue;
      }
      for (final requirement in requirements) {
        final grant = settings.folderGrants[requirement.id];
        if (grant == null || !_samePath(grant.path, requirement.path)) {
          _folderAuthorizations[requirement.id] =
              FolderAuthorization.needsAuthorization(path: requirement.path);
        }
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
    } catch (exception, stackTrace) {
      _fail('finish that', exception, stackTrace, category: 'app');
    } finally {
      isBusy = false;
      progressMessage = null;
      progressValue = null;
      notifyListeners();
      _startLibraryChangeQueue();
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
    } catch (exception, stackTrace) {
      _fail(failure, exception, stackTrace, category: 'media');
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

  /// Logs a failure in full and shows the user a sentence about it.
  void _fail(
    String action,
    Object exception,
    StackTrace stackTrace, {
    required String category,
  }) {
    log.error(
      'Could not $action.',
      category: category,
      error: exception,
      stackTrace: stackTrace,
    );
    _setError(describeFailure(exception, action: action));
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
    _libraryChangeSummaryTimer?.cancel();
    _libraryWatchRecoveryTimer?.cancel();
    unawaited(_libraryWatchSubscription?.cancel());
    unawaited(folderAccess.dispose());
    super.dispose();
  }
}

class _QueuedLibraryChange {
  const _QueuedLibraryChange(this.generation, this.change);

  final int generation;
  final LibraryChange change;
}

enum _MediaMutation { none, added, updated }

class _SourceValidation {
  const _SourceValidation(this.settings, this.errors);

  final AppSettings settings;
  final Map<String, String> errors;

  List<String> get disabledSources => errors.keys.toList(growable: false);
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
