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
import '../services/provider_paths.dart';
import '../services/screenshot_action_service.dart';

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
    this.folderAccess = const PathFolderAccessService(),
    this.providerPaths = const ProviderPathResolver(),
    this.screenshotActions = const NativeScreenshotActionService(),
  });

  final ConfigStore configStore;
  final LibraryScanner scanner;
  final List<ScreenshotProvider> providers;
  final FolderAccessService folderAccess;
  final ProviderPathResolver providerPaths;
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
  NotificationKind? notificationKind;
  String? progressMessage;
  double? progressValue;
  int notificationRevision = 0;
  final List<AppNotification> _notifications = [];
  final Map<String, FolderAuthorization> _folderAuthorizations = {};
  FolderAccessLease? _libraryLease;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

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
      if (usesPersistentFolderAccess) {
        var changed = await _restoreLibraryGrant();
        changed = await _restoreProviderGrants() || changed;
        if (changed) {
          await configStore.save(settings);
        }
      }

      if (!libraryNeedsAuthorization) {
        library = await scanner.scan(settings.outputPath);
      } else {
        library = const MediaLibrary.empty();
        view = LibraryView.settings;
      }
    } catch (exception) {
      _setError('Could not load the library: $exception');
    } finally {
      isInitializing = false;
      notifyListeners();
    }
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

  Future<bool> updateSettings(AppSettings next) async {
    try {
      final outputChanged = !_samePath(
        settings.outputPath,
        next.outputPath,
        allowEmpty: true,
      );
      await configStore.save(next);
      settings = next;
      if (usesPersistentFolderAccess && outputChanged) {
        await _releaseLibraryLease();
      }
      _refreshAuthorizationStates();
      notifyListeners();
      return true;
    } catch (exception) {
      _setError('Could not save settings: $exception');
      notifyListeners();
      return false;
    }
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
      await configStore.save(next);

      final oldLibraryLease = _libraryLease;
      settings = next;
      _folderAuthorizations[specification.request.id] = FolderAuthorization(
        FolderAuthorizationStatus.ready,
        path: lease.grant.path,
      );

      if (target == SettingsFolderTarget.library &&
          usesPersistentFolderAccess) {
        _libraryLease = lease;
        lease = null;
        if (oldLibraryLease != null) {
          await folderAccess.release(oldLibraryLease);
        }
        try {
          library = await scanner.scan(settings.outputPath);
        } catch (_) {
          library = const MediaLibrary.empty();
        }
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
    await _run(() async {
      if (libraryNeedsAuthorization) {
        _setWarning(
          'Library folder access is required. Open Settings and allow access.',
        );
        return;
      }
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
      if (!libraryNeedsAuthorization) {
        _setProgress('Refreshing the library…');
        library = await scanner.scan(settings.outputPath);
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
    unawaited(folderAccess.dispose());
    super.dispose();
  }
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
