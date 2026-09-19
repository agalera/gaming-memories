import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../widgets/library_sidebar.dart';
import '../widgets/screenshot_gallery.dart';
import 'settings_page.dart';

class LibraryShell extends StatefulWidget {
  const LibraryShell({required this.controller, super.key});

  final LibraryController controller;

  @override
  State<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends State<LibraryShell> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.isInitializing) {
      widget.controller.initialize();
    }
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
          header: FHeader(
            title: Text(controller.pageTitle),
            suffixes: [
              FHeaderAction(
                semanticsLabel: 'Refresh library',
                icon: const Icon(FLucideIcons.refreshCw),
                onPress: controller.isBusy ? null : controller.refresh,
              ),
              FHeaderAction(
                semanticsLabel: 'Collect screenshots',
                icon: const Icon(FLucideIcons.hardDriveDownload),
                onPress: controller.isBusy ? null : controller.collect,
              ),
            ],
          ),
          child: Column(
            children: [
              if (controller.isBusy && controller.progressMessage != null)
                _ProgressBanner(
                  message: controller.progressMessage!,
                  value: controller.progressValue,
                ),
              if (controller.message != null || controller.error != null)
                _StatusBanner(
                  message: controller.error ?? controller.message!,
                  isError: controller.error != null,
                ),
              Expanded(child: _content(controller)),
            ],
          ),
        );
      },
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
          '${controller.settings.steam.toJson()}',
        ),
        controller: controller,
      );
    }

    return ScreenshotGallery(
      screenshots: controller.visibleScreenshots,
      description: controller.pageDescription,
      needsSetup: controller.settings.outputPath.trim().isEmpty,
      onSetup: controller.showSettings,
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  const _ProgressBanner({required this.message, required this.value});

  final String message;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final progress = value;
    final percent = progress == null ? null : (progress * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
      color: context.theme.colors.muted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: context.theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (percent != null)
                Text(
                  '$percent%',
                  style: context.theme.typography.body.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (progress == null)
            const FProgress(semanticsLabel: 'Collection in progress')
          else
            FDeterminateProgress(
              value: progress,
              semanticsLabel: 'Collection progress: $percent percent',
            ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final color = isError ? colors.destructive : colors.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: color.withValues(alpha: 0.14),
      child: Row(
        children: [
          Icon(
            isError ? FLucideIcons.alertCircle : FLucideIcons.circleCheck,
            size: 16,
            color: isError ? colors.destructive : colors.foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: context.theme.typography.body.sm.copyWith(
                color: isError ? colors.destructive : colors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
