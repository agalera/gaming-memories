import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';

/// What a running publish shows in place of the Publish button: what it is on
/// now, and how far along it is.
class LibraryPublishToast extends StatelessWidget {
  const LibraryPublishToast({required this.activity, super.key});

  final PublishActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;

    return FToast(
      key: const ValueKey('publish-status-toast'),
      style: FToastStyleDelta.delta(
        padding: const .value(
          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        constraints: const BoxConstraints(),
        iconStyle: .delta(
          color: activity.isStopping ? colors.mutedForeground : colors.primary,
          size: 16,
        ),
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
      icon: const Icon(FLucideIcons.globe),
      title: Text(
        activity.title,
        key: const ValueKey('publish-status-title'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            activity.detail,
            key: const ValueKey('publish-status-detail'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            // A transport that cannot say how far along it is shows movement
            // rather than a bar stuck at nothing.
            child: activity.progress == null
                ? FProgress(
                    key: const ValueKey('publish-status-progress'),
                    semanticsLabel: activity.title,
                  )
                : FDeterminateProgress(
                    key: const ValueKey('publish-status-progress'),
                    value: activity.progress!,
                    semanticsLabel: activity.title,
                  ),
          ),
        ],
      ),
    );
  }
}
