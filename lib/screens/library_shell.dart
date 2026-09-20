import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../controllers/library_controller.dart';
import '../widgets/library_sidebar.dart';
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
    final media = controller.selectedMedia;
    if (media != null) {
      return FHeader.nested(
        title: _breadcrumb(controller),
        titleAlignment: Alignment.centerLeft,
        prefixes: [
          FHeaderAction.back(
            key: const ValueKey('media-back-button'),
            semanticsLabel: 'Back to media',
            onPress: controller.closeMedia,
          ),
        ],
      );
    }

    return FHeader(
      title: controller.view == LibraryView.settings
          ? const Text('Settings')
          : _breadcrumb(controller),
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
    final items = <Widget>[
      FBreadcrumbItem(
        key: const ValueKey('breadcrumb-library'),
        current: controller.view == LibraryView.timeline && !isMediaDetail,
        onPress: controller.view == LibraryView.timeline
            ? (isMediaDetail ? controller.closeMedia : null)
            : controller.showTimeline,
        child: const Text('Library'),
      ),
    ];
    final platform = controller.selectedPlatform ?? media?.platform;
    if (platform != null) {
      items.add(
        FBreadcrumbItem(
          key: ValueKey('breadcrumb-platform-$platform'),
          current: controller.view == LibraryView.platform && !isMediaDetail,
          onPress: controller.view == LibraryView.platform
              ? (isMediaDetail ? controller.closeMedia : null)
              : () => controller.showPlatform(platform),
          child: Text(platform),
        ),
      );
    }
    final game = controller.selectedGame ?? media?.game;
    if (platform != null && game != null) {
      items.add(
        FBreadcrumbItem(
          key: ValueKey('breadcrumb-game-$game'),
          current: controller.view == LibraryView.album && !isMediaDetail,
          onPress: controller.view == LibraryView.album
              ? (isMediaDetail ? controller.closeMedia : null)
              : () => controller.showAlbum(platform, game),
          child: Text(game),
        ),
      );
    }
    final mediaSubAlbumPath = media?.subAlbumPath.trim();
    final subAlbumPath =
        controller.selectedSubAlbumPath ??
        (mediaSubAlbumPath == null || mediaSubAlbumPath.isEmpty
            ? null
            : mediaSubAlbumPath);
    if (platform != null && game != null && subAlbumPath != null) {
      var currentPath = '';
      final segments = p.split(subAlbumPath);
      for (final segment in segments) {
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
            child: Text(segment),
          ),
        );
      }
    }
    if (media != null) {
      items.add(
        FBreadcrumbItem(
          key: ValueKey('breadcrumb-media-${media.path}'),
          current: true,
          child: Text(p.basename(media.path)),
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

    return IndexedStack(
      index: media == null ? 0 : 1,
      children: [
        MediaGallery(
          key: galleryKey,
          media: controller.visibleMedia,
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
          MediaDetailPage(media: media, controller: controller),
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
