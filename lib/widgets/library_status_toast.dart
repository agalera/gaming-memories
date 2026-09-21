import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';

/// The sidebar's library status panel: a toast that stays put, showing what the
/// library is doing and what changed.
class LibraryStatusToast extends StatelessWidget {
  const LibraryStatusToast({required this.activity, super.key});

  final LibraryActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final accent = switch (activity.kind) {
      LibraryActivityKind.attention =>
        colors.brightness == Brightness.dark
            ? const Color(0xfffbbf24)
            : const Color(0xffb45309),
      LibraryActivityKind.idle => colors.mutedForeground,
      _ => colors.primary,
    };

    return FToast(
      key: const ValueKey('library-status-toast'),
      style: FToastStyleDelta.delta(
        padding: const .value(
          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        constraints: const BoxConstraints(),
        iconStyle: .delta(color: accent, size: 16),
        iconSpacing: 8,
        titleSpacing: 3,
        titleTextStyle: .delta(
          fontSize: context.theme.typography.body.xs.fontSize,
          fontWeight: FontWeight.w600,
        ),
        descriptionTextStyle: .delta(
          fontSize: context.theme.typography.body.xs.fontSize,
          color: colors.mutedForeground,
        ),
      ),
      icon: Icon(switch (activity.kind) {
        LibraryActivityKind.idle => FLucideIcons.circleCheck,
        LibraryActivityKind.attention => FLucideIcons.alertTriangle,
        LibraryActivityKind.detected => FLucideIcons.clock,
        LibraryActivityKind.updating => FLucideIcons.refreshCw,
        LibraryActivityKind.refreshing => FLucideIcons.refreshCw,
      }),
      title: Text(
        activity.title,
        key: const ValueKey('library-status-title'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      description: _description(),
    );
  }

  Widget? _description() {
    final detail = activity.detail;
    if (detail == null && !activity.isRunning) {
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (detail != null)
          Text(
            detail,
            key: const ValueKey('library-status-detail'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (activity.isRunning) ...[
          if (detail != null) const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: activity.progress == null
                ? FProgress(
                    key: const ValueKey('library-status-progress'),
                    semanticsLabel: activity.title,
                  )
                : FDeterminateProgress(
                    key: const ValueKey('library-status-progress'),
                    value: activity.progress!,
                    semanticsLabel: activity.title,
                  ),
          ),
        ],
      ],
    );
  }
}
