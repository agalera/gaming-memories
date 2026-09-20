import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

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
  FToasterEntry? _progressToast;
  int _lastNotificationRevision = -1;
  bool _toastSyncScheduled = false;

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
        controller.isBusy && controller.progressMessage != null;

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

    _lastNotificationRevision = controller.notificationRevision;
    final error = controller.error;
    final message = controller.message;
    if (error != null) {
      _showResultToast(error, isError: true);
    } else if (message != null) {
      _showResultToast(message, isError: false);
    }
  }

  void _showResultToast(String message, {required bool isError}) {
    final revision = widget.controller.notificationRevision;
    showRawFToast(
      context: context,
      alignment: FToastAlignment.bottomRight,
      variant: isError ? FToastVariant.destructive : FToastVariant.primary,
      duration: isError ? null : const Duration(seconds: 5),
      builder: (context, entry) => FToast(
        key: ValueKey('notification-toast-$revision'),
        variant: isError ? FToastVariant.destructive : FToastVariant.primary,
        icon: Icon(
          isError ? FLucideIcons.alertCircle : FLucideIcons.circleCheck,
        ),
        title: Text(message),
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;

        return FScaffold(
          childPad: false,
          sidebar: LibrarySidebar(controller: controller),
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
        title: Text(media.game),
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
      title: Text(controller.pageTitle),
      suffixes: [
        FHeaderAction(
          semanticsLabel: 'Refresh library',
          icon: const Icon(FLucideIcons.refreshCw),
          onPress: controller.isBusy ? null : controller.refresh,
        ),
        FHeaderAction(
          semanticsLabel: 'Collect media',
          icon: const Icon(FLucideIcons.hardDriveDownload),
          onPress: controller.isBusy ? null : controller.collect,
        ),
      ],
    );
  }

  Widget _content(LibraryController controller) {
    if (controller.isInitializing) {
      return const Center(child: FCircularProgress());
    }

    if (controller.view == LibraryView.settings) {
      return SettingsPage(
        key: ValueKey(
          '${controller.settings.outputPath}|'
          '${controller.settings.diabloIV.enabled}|'
          '${controller.settings.diabloIV.sourcePath}|'
          '${controller.settings.guildWars2.enabled}|'
          '${controller.settings.guildWars2.sourcePath}|'
          '${controller.settings.steam.toJson()}',
        ),
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
          description: controller.pageDescription,
          needsSetup: controller.settings.outputPath.trim().isEmpty,
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
