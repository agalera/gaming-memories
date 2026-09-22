import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/app_settings.dart';
import '../models/library.dart';
import 'library_publish_toast.dart';
import 'library_scan_toast.dart';
import 'library_status_toast.dart';

class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({required this.controller, this.width = 256, super.key});

  final LibraryController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    final activity = controller.libraryActivity;
    final scanActivity = controller.scanActivity;
    final albumGroups = controller.platformFolders.map((platform) {
      return _PlatformSidebarItem(
        key: ValueKey('platform-${platform.name}'),
        platform: platform.name,
        selected:
            controller.view == LibraryView.platform &&
            controller.selectedPlatform == platform.name,
        onPress: () => controller.showPlatform(platform.name),
        children: platform.children.map((game) {
          final selected =
              controller.view == LibraryView.album &&
              controller.selectedPlatform == platform.name &&
              controller.selectedGame == game.name;

          return _AlbumSidebarItem(
            key: ValueKey('game-${platform.name}-${game.name}'),
            itemKey: 'game-${platform.name}-${game.name}',
            name: game.name,
            icon: FLucideIcons.gamepad2,
            selected: selected,
            onPress: () => controller.showAlbum(platform.name, game.name),
            onExpand: game.childrenLoaded
                ? null
                : () => controller.loadSubAlbums(platform.name, game.name),
            children: game.children
                .map(
                  (subAlbum) =>
                      _subAlbumItem(platform.name, game.name, subAlbum),
                )
                .toList(),
          );
        }).toList(),
      );
    }).toList();

    return FSidebar(
      key: const ValueKey('library-sidebar'),
      style: FSidebarStyleDelta.delta(
        constraints: BoxConstraints.tightFor(width: width),
        contentPadding: const .value(EdgeInsets.only(top: 8)),
        footerPadding: const .value(EdgeInsets.zero),
        groupStyle: const FSidebarGroupStyleDelta.delta(
          childrenPadding: .value(EdgeInsets.zero),
        ),
      ),
      footer: DecoratedBox(
        key: const ValueKey('sidebar-footer'),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.theme.colors.border)),
        ),
        child: Padding(
          key: const ValueKey('sidebar-footer-padding'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  key: const ValueKey('sidebar-status-row'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: LibraryStatusToast(activity: activity)),
                    const SizedBox(width: 8),
                    FTooltip(
                      tipBuilder: (context, _) => const Text('Force refresh'),
                      child: FButton.icon(
                        key: const ValueKey('refresh-sidebar-button'),
                        variant: FButtonVariant.outline,
                        semanticsLabel: 'Force refresh the library',
                        onPress: activity.isRunning || scanActivity.isRunning
                            ? null
                            : controller.refresh,
                        child: const Icon(FLucideIcons.refreshCw),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              IntrinsicHeight(
                child: Row(
                  key: const ValueKey('sidebar-scan-row'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: LibraryScanToast(activity: scanActivity)),
                    const SizedBox(width: 8),
                    FTooltip(
                      tipBuilder: (context, _) =>
                          const Text('Scan for new captures'),
                      child: FButton.icon(
                        key: const ValueKey('scan-sidebar-button'),
                        variant: FButtonVariant.outline,
                        semanticsLabel: 'Scan for new captures',
                        onPress: activity.isRunning || scanActivity.isRunning
                            ? null
                            : controller.collect,
                        child: const Icon(FLucideIcons.hardDriveDownload),
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.canPublish) ...[
                const SizedBox(height: 8),
                _PublishButton(controller: controller),
              ],
              const SizedBox(height: 8),
              FButton(
                key: const ValueKey('settings-sidebar-button'),
                variant: FButtonVariant.outline,
                selected: controller.view == LibraryView.settings,
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.start,
                prefix: const Icon(FLucideIcons.settings),
                onPress: controller.showSettings,
                child: const Expanded(child: Text('Settings')),
              ),
            ],
          ),
        ),
      ),
      children: [
        FSidebarGroup(
          children: [
            FSidebarItem(
              icon: const Icon(FLucideIcons.clock),
              label: const Text('Timeline'),
              selected: controller.view == LibraryView.timeline,
              onPress: controller.showTimeline,
            ),
            if (controller.isAlbumTreeLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox.square(
                    key: ValueKey('albums-loading-spinner'),
                    dimension: 18,
                    child: FCircularProgress(),
                  ),
                ),
              )
            else if (albumGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  'Your albums will appear here.',
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              )
            else
              ...albumGroups,
          ],
        ),
      ],
    );
  }

  Widget _subAlbumItem(String platform, String game, LibraryFolder subAlbum) {
    return _AlbumSidebarItem(
      key: ValueKey('sub-album-$platform-$game-${subAlbum.relativePath}'),
      itemKey: 'sub-album-$platform-$game-${subAlbum.relativePath}',
      name: subAlbum.name,
      icon: FLucideIcons.folderOpen,
      selected:
          controller.view == LibraryView.subAlbum &&
          controller.selectedPlatform == platform &&
          controller.selectedGame == game &&
          controller.selectedSubAlbumPath == subAlbum.relativePath,
      onPress: () =>
          controller.showSubAlbum(platform, game, subAlbum.relativePath),
      children: subAlbum.children
          .map((child) => _subAlbumItem(platform, game, child))
          .toList(),
    );
  }
}

class _AlbumSidebarItem extends StatefulWidget {
  const _AlbumSidebarItem({
    required this.itemKey,
    required this.name,
    required this.icon,
    required this.selected,
    required this.onPress,
    required this.children,
    this.onExpand,
    super.key,
  });

  final String itemKey;
  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onPress;
  final List<Widget> children;
  final Future<void> Function()? onExpand;

  @override
  State<_AlbumSidebarItem> createState() => _AlbumSidebarItemState();
}

class _AlbumSidebarItemState extends State<_AlbumSidebarItem> {
  bool _expanded = false;
  bool _isLoading = false;

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }

    final onExpand = widget.onExpand;
    if (onExpand != null) {
      setState(() => _isLoading = true);
      await onExpand();
      if (!mounted) {
        return;
      }
    }
    setState(() {
      _isLoading = false;
      _expanded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FButton(
                key: ValueKey('${widget.itemKey}-label'),
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                selected: widget.selected,
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.start,
                semanticsLabel: 'Show ${widget.name} album',
                prefix: Icon(widget.icon),
                onPress: widget.onPress,
                child: Expanded(
                  child: Text(widget.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            if (widget.children.isNotEmpty || widget.onExpand != null) ...[
              const SizedBox(width: 2),
              FButton.icon(
                key: ValueKey('${widget.itemKey}-toggle'),
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                selected: widget.selected,
                semanticsLabel: _expanded
                    ? 'Collapse ${widget.name} sub-albums'
                    : 'Expand ${widget.name} sub-albums',
                onPress: _isLoading ? null : _toggle,
                child: _isLoading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: FCircularProgress(),
                      )
                    : AnimatedRotation(
                        turns: _expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: const Icon(FLucideIcons.chevronRight),
                      ),
              ),
            ],
          ],
        ),
        if (_expanded && widget.children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (
                  var index = 0;
                  index < widget.children.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(height: 4),
                  widget.children[index],
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Renders the gallery and uploads it in one press. A key with a passphrase
/// asks for it first, once per run of the app.
class _PublishButton extends StatelessWidget {
  const _PublishButton({required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final activity = controller.publishActivity;

    // A running publish takes the button's place, so the sidebar shows what
    // it is doing and offers the one action left: stopping it.
    if (activity.isRunning) {
      return IntrinsicHeight(
        key: const ValueKey('publish-running-row'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: LibraryPublishToast(activity: activity)),
            const SizedBox(width: 8),
            FTooltip(
              tipBuilder: (context, _) => Text(
                activity.isStopping
                    ? 'Stopping the publish'
                    : 'Stop publishing',
              ),
              child: FButton.icon(
                key: const ValueKey('publish-stop-button'),
                variant: FButtonVariant.outline,
                semanticsLabel: 'Stop publishing',
                onPress: activity.isStopping ? null : controller.cancelPublish,
                child: const Icon(FLucideIcons.square),
              ),
            ),
          ],
        ),
      );
    }

    return FTooltip(
      tipBuilder: (context, _) => Text(activity.detail),
      child: FButton(
        key: const ValueKey('publish-sidebar-button'),
        variant: FButtonVariant.outline,
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.start,
        prefix: const Icon(FLucideIcons.globe),
        onPress: () => _publish(context),
        child: Expanded(child: Text(activity.title)),
      ),
    );
  }

  Future<void> _publish(BuildContext context) async {
    final needed = await controller.publishSecretNeeded();
    if (needed == PublishSecretKind.none) {
      await controller.publish();
      return;
    }
    if (!context.mounted) {
      return;
    }
    final secret = await _askSecret(context, needed);
    if (secret == null) {
      return;
    }
    await controller.publish(secret: secret);
  }

  Future<String?> _askSecret(BuildContext context, PublishSecretKind kind) {
    final field = TextEditingController();
    final target = controller.settings.publish.target;
    final isPassword = kind == PublishSecretKind.password;
    final title = isPassword
        ? 'Password for ${target.username}@${target.host}'
        : 'SSH key passphrase';

    return showFDialog<String>(
      context: context,
      builder: (dialogContext, _, animation) => FDialog(
        animation: animation,
        semanticsLabel: title,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.theme.typography.display.sm),
                const SizedBox(height: 8),
                Text(
                  isPassword
                      ? 'This publish signs in with a password. It is kept in '
                            'memory until Gaming Memories closes, and is '
                            'never saved.'
                      : 'The key this publish uses is protected. The '
                            'passphrase is kept in memory until Gaming '
                            'Memories closes, and is never saved.',
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 18),
                FTextField.password(
                  key: const ValueKey('publish-secret-field'),
                  control: FTextFieldControl.managed(controller: field),
                  label: Text(isPassword ? 'Password' : 'Passphrase'),
                  autofocus: true,
                  onSubmit: (value) => Navigator.of(dialogContext).pop(value),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FButton(
                      variant: FButtonVariant.ghost,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FButton(
                      key: const ValueKey('publish-secret-confirm'),
                      mainAxisSize: MainAxisSize.min,
                      onPress: () =>
                          Navigator.of(dialogContext).pop(field.text),
                      child: const Text('Publish'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(field.dispose);
  }
}

class _PlatformSidebarItem extends StatefulWidget {
  const _PlatformSidebarItem({
    required this.platform,
    required this.selected,
    required this.onPress,
    required this.children,
    super.key,
  });

  final String platform;
  final bool selected;
  final VoidCallback onPress;
  final List<Widget> children;

  @override
  State<_PlatformSidebarItem> createState() => _PlatformSidebarItemState();
}

class _PlatformSidebarItemState extends State<_PlatformSidebarItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FButton(
                key: ValueKey('platform-label-${widget.platform}'),
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                selected: widget.selected,
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.start,
                semanticsLabel: 'Show ${widget.platform} timeline',
                prefix: const Icon(FLucideIcons.monitor),
                onPress: widget.onPress,
                child: Expanded(
                  child: Text(widget.platform, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            const SizedBox(width: 2),
            FButton.icon(
              key: ValueKey('platform-toggle-${widget.platform}'),
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.sm,
              selected: widget.selected,
              semanticsLabel: _expanded
                  ? 'Collapse ${widget.platform} albums'
                  : 'Expand ${widget.platform} albums',
              onPress: () => setState(() => _expanded = !_expanded),
              child: AnimatedRotation(
                turns: _expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(FLucideIcons.chevronRight),
              ),
            ),
          ],
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (
                  var index = 0;
                  index < widget.children.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(height: 4),
                  widget.children[index],
                ],
              ],
            ),
          ),
      ],
    );
  }
}
