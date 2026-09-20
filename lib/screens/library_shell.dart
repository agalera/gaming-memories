import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../controllers/library_controller.dart';
import '../models/library.dart';
import '../widgets/library_sidebar.dart';
import '../widgets/screenshot_actions.dart';
import '../widgets/screenshot_gallery.dart';
import 'settings_page.dart';
import 'screenshot_detail_page.dart';

class LibraryShell extends StatefulWidget {
  const LibraryShell({required this.controller, super.key});

  final LibraryController controller;

  @override
  State<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends State<LibraryShell> {
  static const _defaultSidebarWidth = 256.0;
  static const _minimumSidebarWidth = 220.0;
  static const _maximumSidebarWidth = 480.0;

  FToasterEntry? _progressToast;
  final ScrollController _breadcrumbScrollController = ScrollController();
  int _lastNotificationRevision = -1;
  bool _toastSyncScheduled = false;
  double _sidebarWidth = _defaultSidebarWidth;
  String? _breadcrumbMediaPath;
  _MediaFilter _mediaFilter = _MediaFilter.all;
  _MediaSort _mediaSort = _MediaSort.descending;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleToastSync);
    _scheduleToastSync();
    if (widget.controller.isInitializing) {
      widget.controller.initialize();
    }
  }

  @override
  void didUpdateWidget(LibraryShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }

    oldWidget.controller.removeListener(_scheduleToastSync);
    _progressToast?.dismiss();
    _progressToast = null;
    _lastNotificationRevision = -1;
    widget.controller.addListener(_scheduleToastSync);
    _scheduleToastSync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleToastSync);
    _progressToast = null;
    _breadcrumbScrollController.dispose();
    super.dispose();
  }

  void _scheduleToastSync() {
    if (!mounted || _toastSyncScheduled) {
      return;
    }

    _toastSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _toastSyncScheduled = false;
      if (mounted) {
        _syncToasts();
      }
    });
  }

  void _syncToasts() {
    final controller = widget.controller;
    final showProgress =
        (controller.isBusy || controller.isTimelineRefreshing) &&
        controller.progressMessage != null;

    if (showProgress && _progressToast?.showing != true) {
      _progressToast = showRawFToast(
        context: context,
        alignment: FToastAlignment.bottomRight,
        duration: null,
        swipeToDismiss: const [],
        builder: (context, entry) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) => _ProgressToast(
            message: controller.progressMessage ?? 'Please wait…',
            value: controller.progressValue,
          ),
        ),
      );
    } else if (!showProgress && _progressToast != null) {
      _progressToast!.dismiss();
      _progressToast = null;
    }

    if (_lastNotificationRevision == controller.notificationRevision) {
      return;
    }

    final notifications = controller.notifications
        .where(
          (notification) => notification.revision > _lastNotificationRevision,
        )
        .toList(growable: false);
    _lastNotificationRevision = controller.notificationRevision;
    for (final notification in notifications) {
      _showResultToast(notification);
    }
  }

  void _showResultToast(AppNotification notification) {
    final revision = notification.revision;
    final kind = notification.kind;
    final isError = kind == NotificationKind.error;
    final warningColor = context.theme.colors.brightness == Brightness.dark
        ? const Color(0xfffbbf24)
        : const Color(0xffb45309);
    showRawFToast(
      context: context,
      alignment: FToastAlignment.bottomRight,
      variant: isError ? FToastVariant.destructive : FToastVariant.primary,
      duration: isError ? null : const Duration(seconds: 5),
      builder: (context, entry) => FToast(
        key: ValueKey('notification-toast-$revision'),
        variant: isError ? FToastVariant.destructive : FToastVariant.primary,
        style: kind == NotificationKind.warning
            ? FToastStyleDelta.delta(
                iconStyle: .delta(color: warningColor),
                titleTextStyle: .delta(color: warningColor),
                descriptionTextStyle: .delta(color: warningColor),
              )
            : const FToastStyleDelta.context(),
        icon: Icon(switch (kind) {
          NotificationKind.success => FLucideIcons.circleCheck,
          NotificationKind.warning => FLucideIcons.alertTriangle,
          NotificationKind.error => FLucideIcons.alertCircle,
        }),
        title: Text(notification.message),
        suffix: isError
            ? FButton.icon(
                key: ValueKey('notification-toast-close-$revision'),
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                semanticsLabel: 'Close error notification',
                onPress: entry.dismiss,
                child: const Icon(FLucideIcons.x),
              )
            : null,
      ),
    );
  }

  void _resizeSidebar(DragUpdateDetails details) {
    final width = (_sidebarWidth + details.delta.dx)
        .clamp(_minimumSidebarWidth, _maximumSidebarWidth)
        .toDouble();
    if (width == _sidebarWidth) {
      return;
    }

    setState(() => _sidebarWidth = width);
  }

  void _showBreadcrumbEnd(String mediaPath) {
    if (_breadcrumbMediaPath == mediaPath) {
      return;
    }

    _breadcrumbMediaPath = mediaPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _breadcrumbMediaPath != mediaPath ||
          !_breadcrumbScrollController.hasClients) {
        return;
      }
      _breadcrumbScrollController.jumpTo(
        _breadcrumbScrollController.position.maxScrollExtent,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;

        return FScaffold(
          childPad: false,
          sidebar: SizedBox(
            width: _sidebarWidth,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LibrarySidebar(controller: controller, width: _sidebarWidth),
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: 8,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      key: const ValueKey('sidebar-resize-handle'),
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: _resizeSidebar,
                    ),
                  ),
                ),
              ],
            ),
          ),
          header: _header(controller),
          child: _content(controller),
        );
      },
    );
  }

  Widget _header(LibraryController controller) {
    if (controller.view == LibraryView.settings) {
      return const FHeader(title: Text('Settings'));
    }

    final media = controller.selectedMedia;
    final visibleMedia = controller.visibleMedia;
    final actions = media != null
        ? MediaActionButtons(controller: controller, media: media)
        : visibleMedia.isEmpty
        ? null
        : _GalleryActions(
            media: visibleMedia,
            filter: _mediaFilter,
            sort: _mediaSort,
            onFilterChanged: (value) => setState(() => _mediaFilter = value),
            onSortChanged: (value) => setState(() => _mediaSort = value),
          );

    return FHeader(
      key: const ValueKey('content-header'),
      title: _ContentHeader(
        breadcrumb: _breadcrumb(controller),
        actions: actions,
        onBack: media == null ? null : controller.closeMedia,
      ),
    );
  }

  Widget _breadcrumb(LibraryController controller) {
    final media = controller.selectedMedia;
    final isMediaDetail = media != null;
    if (media == null) {
      _breadcrumbMediaPath = null;
    } else {
      _showBreadcrumbEnd(media.path);
    }
    final platform = controller.selectedPlatform ?? media?.platform;
    final game = controller.selectedGame ?? media?.game;
    final mediaSubAlbumPath = media?.subAlbumPath.trim();
    final subAlbumPath =
        controller.selectedSubAlbumPath ??
        (mediaSubAlbumPath == null || mediaSubAlbumPath.isEmpty
            ? null
            : mediaSubAlbumPath);
    final subAlbumSegments = subAlbumPath == null
        ? const <String>[]
        : p.split(subAlbumPath);
    final items = <Widget>[
      FBreadcrumbItem(
        key: const ValueKey('breadcrumb-library'),
        current: controller.view == LibraryView.timeline && !isMediaDetail,
        onPress: controller.view == LibraryView.timeline
            ? (isMediaDetail ? controller.closeMedia : null)
            : controller.showTimeline,
        child: Text(
          'Library',
          style: TextStyle(
            fontWeight: platform == null ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    ];
    if (platform != null) {
      items.add(
        FBreadcrumbItem(
          key: ValueKey('breadcrumb-platform-$platform'),
          current: controller.view == LibraryView.platform && !isMediaDetail,
          onPress: controller.view == LibraryView.platform
              ? (isMediaDetail ? controller.closeMedia : null)
              : () => controller.showPlatform(platform),
          child: Text(
            platform,
            style: TextStyle(
              fontWeight: game == null ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      );
    }
    if (platform != null && game != null) {
      items.add(
        FBreadcrumbItem(
          key: ValueKey('breadcrumb-game-$game'),
          current: controller.view == LibraryView.album && !isMediaDetail,
          onPress: controller.view == LibraryView.album
              ? (isMediaDetail ? controller.closeMedia : null)
              : () => controller.showAlbum(platform, game),
          child: Text(
            game,
            style: TextStyle(
              fontWeight: subAlbumSegments.isEmpty
                  ? FontWeight.w700
                  : FontWeight.w400,
            ),
          ),
        ),
      );
    }
    if (platform != null && game != null && subAlbumPath != null) {
      var currentPath = '';
      for (var index = 0; index < subAlbumSegments.length; index++) {
        final segment = subAlbumSegments[index];
        currentPath = currentPath.isEmpty
            ? segment
            : p.join(currentPath, segment);
        final targetPath = currentPath;
        final isCurrentSubAlbum =
            controller.view == LibraryView.subAlbum &&
            controller.selectedPlatform == platform &&
            controller.selectedGame == game &&
            controller.selectedSubAlbumPath == targetPath;
        items.add(
          FBreadcrumbItem(
            key: ValueKey('breadcrumb-folder-$targetPath'),
            current: isCurrentSubAlbum && !isMediaDetail,
            onPress: isCurrentSubAlbum
                ? (isMediaDetail ? controller.closeMedia : null)
                : () => controller.showSubAlbum(platform, game, targetPath),
            child: Text(
              segment,
              style: TextStyle(
                fontWeight: index == subAlbumSegments.length - 1
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
        );
      }
    }
    if (media != null) {
      items.add(
        FBreadcrumbItem(
          key: ValueKey('breadcrumb-media-${media.path}'),
          current: true,
          child: Text(
            p.basename(media.path),
            style: const TextStyle(fontWeight: FontWeight.w400),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      controller: _breadcrumbScrollController,
      scrollDirection: Axis.horizontal,
      child: FBreadcrumb(children: items),
    );
  }

  Widget _content(LibraryController controller) {
    if (controller.isInitializing) {
      return const Center(child: FCircularProgress());
    }

    if (controller.view == LibraryView.settings) {
      return SettingsPage(
        key: const ValueKey('settings-page'),
        controller: controller,
      );
    }

    final galleryKey = ValueKey(
      'gallery-${controller.view.name}-'
      '${controller.selectedPlatform}-${controller.selectedGame}-'
      '${controller.selectedSubAlbumPath}',
    );
    final media = controller.selectedMedia;
    final galleryMedia = _filteredMedia(controller.visibleMedia);

    return IndexedStack(
      index: media == null ? 0 : 1,
      children: [
        MediaGallery(
          key: galleryKey,
          media: galleryMedia,
          games: controller.view == LibraryView.platform
              ? controller.gameFolders
              : const [],
          folders:
              controller.view == LibraryView.album ||
                  controller.view == LibraryView.subAlbum
              ? controller.folderListing.folders
              : const [],
          isLoading: controller.isViewLoading,
          isTimelineRefreshing:
              controller.view == LibraryView.timeline &&
              controller.isTimelineRefreshing,
          needsSetup:
              controller.settings.outputPath.trim().isEmpty ||
              controller.libraryNeedsAuthorization,
          onSetup: controller.showSettings,
          controller: controller,
        ),
        if (media == null)
          const SizedBox.shrink()
        else
          MediaDetailPage(media: media),
      ],
    );
  }

  List<MediaItem> _filteredMedia(List<MediaItem> source) {
    final filtered = source
        .where(
          (media) => switch (_mediaFilter) {
            _MediaFilter.all => true,
            _MediaFilter.screenshots => !media.isVideo,
            _MediaFilter.clips => media.isVideo,
          },
        )
        .toList();
    filtered.sort((left, right) {
      var result = left.capturedAt.compareTo(right.capturedAt);
      if (result == 0) {
        result = left.path.compareTo(right.path);
      }
      return _mediaSort == _MediaSort.ascending ? result : -result;
    });
    return List.unmodifiable(filtered);
  }
}

enum _MediaFilter { all, screenshots, clips }

enum _MediaSort { ascending, descending }

class _ContentHeader extends StatelessWidget {
  const _ContentHeader({
    required this.breadcrumb,
    required this.actions,
    required this.onBack,
  });

  final Widget breadcrumb;
  final Widget? actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final path = Row(
      children: [
        if (onBack != null) ...[
          FButton.icon(
            key: const ValueKey('media-back-button'),
            variant: FButtonVariant.ghost,
            size: FButtonSizeVariant.sm,
            semanticsLabel: 'Back to media',
            onPress: onBack,
            child: const Icon(FLucideIcons.arrowLeft),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: breadcrumb),
      ],
    );
    final actions = this.actions;
    if (actions == null) {
      return path;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 850) {
          return Row(
            children: [
              Expanded(child: path),
              const SizedBox(width: 16),
              actions,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            path,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        );
      },
    );
  }
}

class _GalleryActions extends StatelessWidget {
  const _GalleryActions({
    required this.media,
    required this.filter,
    required this.sort,
    required this.onFilterChanged,
    required this.onSortChanged,
  });

  final List<MediaItem> media;
  final _MediaFilter filter;
  final _MediaSort sort;
  final ValueChanged<_MediaFilter> onFilterChanged;
  final ValueChanged<_MediaSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final screenshots = media.where((item) => !item.isVideo).length;
    final clips = media.length - screenshots;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          key: const ValueKey('media-filter-control'),
          width: 180,
          child: FSelect<_MediaFilter>(
            key: const ValueKey('media-filter-select'),
            control: FSelectControl.lifted(
              value: filter,
              onChange: (value) {
                if (value != null) {
                  onFilterChanged(value);
                }
              },
            ),
            size: FTextFieldSizeVariant.sm,
            items: {
              'All (${media.length})': _MediaFilter.all,
              'Screenshots ($screenshots)': _MediaFilter.screenshots,
              'Clips ($clips)': _MediaFilter.clips,
            },
          ),
        ),
        SizedBox(
          key: const ValueKey('media-sort-control'),
          width: 150,
          child: FSelect<_MediaSort>(
            key: const ValueKey('media-sort-select'),
            control: FSelectControl.lifted(
              value: sort,
              onChange: (value) {
                if (value != null) {
                  onSortChanged(value);
                }
              },
            ),
            size: FTextFieldSizeVariant.sm,
            items: const {
              'Ascending': _MediaSort.ascending,
              'Descending': _MediaSort.descending,
            },
          ),
        ),
      ],
    );
  }
}

class _ProgressToast extends StatelessWidget {
  const _ProgressToast({required this.message, required this.value});

  final String message;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final progress = value;
    final percent = progress == null ? null : (progress * 100).round();

    return FToast(
      key: const ValueKey('progress-toast'),
      icon: const SizedBox.square(dimension: 18, child: FCircularProgress()),
      title: Text(message),
      description: SizedBox(
        width: 280,
        child: Row(
          children: [
            Expanded(
              child: progress == null
                  ? const FProgress(semanticsLabel: 'Task in progress')
                  : FDeterminateProgress(
                      value: progress,
                      semanticsLabel: 'Task progress: $percent percent',
                    ),
            ),
            if (percent != null) ...[
              const SizedBox(width: 10),
              Text('$percent%'),
            ],
          ],
        ),
      ),
    );
  }
}
