import 'dart:async';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/library.dart';

class MediaContextMenu extends StatelessWidget {
  const MediaContextMenu({
    required this.controller,
    required this.media,
    required this.child,
    super.key,
  });

  final LibraryController controller;
  final MediaItem media;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FContextMenu(
      key: ValueKey('media-context-menu-${media.path}'),
      secondaryPress: true,
      menu: [
        FItemGroup(
          children: [
            FItem(
              key: ValueKey('media-menu-open-${media.path}'),
              prefix: const Icon(FLucideIcons.folderOpen),
              title: Text(controller.screenshotActions.openLocationLabel),
              onPress: () => unawaited(controller.openMediaLocation(media)),
            ),
            if (!media.isVideo)
              FItem(
                key: ValueKey('media-menu-copy-image-${media.path}'),
                prefix: const Icon(FLucideIcons.fileImage),
                title: const Text('Copy image'),
                onPress: () => unawaited(controller.copyMediaImage(media)),
              ),
            FItem(
              key: ValueKey('media-menu-copy-path-${media.path}'),
              prefix: const Icon(FLucideIcons.copy),
              title: const Text('Copy path'),
              onPress: () => unawaited(controller.copyMediaPath(media)),
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}

class MediaActionButtons extends StatelessWidget {
  const MediaActionButtons({
    required this.controller,
    required this.media,
    super.key,
  });

  final LibraryController controller;
  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FButton(
          key: const ValueKey('media-open-location'),
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          mainAxisSize: MainAxisSize.min,
          prefix: const Icon(FLucideIcons.folderOpen),
          onPress: () => unawaited(controller.openMediaLocation(media)),
          child: Text(controller.screenshotActions.openLocationLabel),
        ),
        if (!media.isVideo)
          FButton(
            key: const ValueKey('media-copy-image'),
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.sm,
            mainAxisSize: MainAxisSize.min,
            prefix: const Icon(FLucideIcons.fileImage),
            onPress: () => unawaited(controller.copyMediaImage(media)),
            child: const Text('Copy image'),
          ),
        FButton(
          key: const ValueKey('media-copy-path'),
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          mainAxisSize: MainAxisSize.min,
          prefix: const Icon(FLucideIcons.copy),
          onPress: () => unawaited(controller.copyMediaPath(media)),
          child: const Text('Copy path'),
        ),
      ],
    );
  }
}
