import 'dart:async';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/library.dart';

class ScreenshotContextMenu extends StatelessWidget {
  const ScreenshotContextMenu({
    required this.controller,
    required this.screenshot,
    required this.child,
    super.key,
  });

  final LibraryController controller;
  final ScreenshotItem screenshot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FContextMenu(
      key: ValueKey('screenshot-context-menu-${screenshot.path}'),
      secondaryPress: true,
      menu: [
        FItemGroup(
          children: [
            FItem(
              key: ValueKey('screenshot-menu-open-${screenshot.path}'),
              prefix: const Icon(FLucideIcons.folderOpen),
              title: Text(controller.screenshotActions.openLocationLabel),
              onPress: () =>
                  unawaited(controller.openScreenshotLocation(screenshot)),
            ),
            FItem(
              key: ValueKey('screenshot-menu-copy-image-${screenshot.path}'),
              prefix: const Icon(FLucideIcons.fileImage),
              title: const Text('Copy image'),
              onPress: () =>
                  unawaited(controller.copyScreenshotImage(screenshot)),
            ),
            FItem(
              key: ValueKey('screenshot-menu-copy-path-${screenshot.path}'),
              prefix: const Icon(FLucideIcons.copy),
              title: const Text('Copy path'),
              onPress: () =>
                  unawaited(controller.copyScreenshotPath(screenshot)),
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}

class ScreenshotActionButtons extends StatelessWidget {
  const ScreenshotActionButtons({
    required this.controller,
    required this.screenshot,
    super.key,
  });

  final LibraryController controller;
  final ScreenshotItem screenshot;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FButton(
          key: const ValueKey('screenshot-open-location'),
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          mainAxisSize: MainAxisSize.min,
          prefix: const Icon(FLucideIcons.folderOpen),
          onPress: () =>
              unawaited(controller.openScreenshotLocation(screenshot)),
          child: Text(controller.screenshotActions.openLocationLabel),
        ),
        FButton(
          key: const ValueKey('screenshot-copy-image'),
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          mainAxisSize: MainAxisSize.min,
          prefix: const Icon(FLucideIcons.fileImage),
          onPress: () => unawaited(controller.copyScreenshotImage(screenshot)),
          child: const Text('Copy image'),
        ),
        FButton(
          key: const ValueKey('screenshot-copy-path'),
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          mainAxisSize: MainAxisSize.min,
          prefix: const Icon(FLucideIcons.copy),
          onPress: () => unawaited(controller.copyScreenshotPath(screenshot)),
          child: const Text('Copy path'),
        ),
      ],
    );
  }
}
