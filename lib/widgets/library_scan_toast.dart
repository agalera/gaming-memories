import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';

/// The provider scan's idle prompt and live progress surface.
class LibraryScanToast extends StatelessWidget {
  const LibraryScanToast({required this.activity, super.key});

  final LibraryScanActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final accent = activity.isRunning ? colors.primary : colors.mutedForeground;

    return FToast(
      key: const ValueKey('scan-status-toast'),
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
      icon: const Icon(FLucideIcons.hardDriveDownload),
      title: Text(
        activity.title,
        key: const ValueKey('scan-status-title'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            activity.detail,
            key: const ValueKey('scan-status-detail'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (activity.isRunning) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: activity.progress == null
                  ? FProgress(
                      key: const ValueKey('scan-status-progress'),
                      semanticsLabel: activity.title,
                    )
                  : FDeterminateProgress(
                      key: const ValueKey('scan-status-progress'),
                      value: activity.progress!,
                      semanticsLabel: activity.title,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
