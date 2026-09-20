import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/library.dart';

class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({required this.controller, super.key});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
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
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: context.theme.colors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                FLucideIcons.sparkles,
                size: 18,
                color: context.theme.colors.primaryForeground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Gaming Memories',
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FButton(
                  key: const ValueKey('refresh-sidebar-button'),
                  variant: FButtonVariant.outline,
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.start,
                  prefix: const Icon(FLucideIcons.refreshCw),
                  onPress: controller.isBusy || controller.isTimelineRefreshing
                      ? null
                      : controller.refresh,
                  child: const Expanded(child: Text('Refresh')),
                ),
                const SizedBox(height: 8),
                FButton(
                  key: const ValueKey('scan-sidebar-button'),
                  variant: FButtonVariant.outline,
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.start,
                  prefix: const Icon(FLucideIcons.hardDriveDownload),
                  onPress: controller.isBusy || controller.isTimelineRefreshing
                      ? null
                      : controller.collect,
                  child: const Expanded(child: Text('Scan')),
                ),
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
        ],
      ),
      children: [
        FSidebarGroup(
          label: const Text('LIBRARY'),
          children: [
            FSidebarItem(
              icon: const Icon(FLucideIcons.clock),
              label: const Text('Timeline'),
              selected: controller.view == LibraryView.timeline,
              onPress: controller.showTimeline,
            ),
          ],
        ),
        FSidebarGroup(
          label: const Text('ALBUMS'),
          children: controller.isAlbumTreeLoading
              ? const [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox.square(
                        key: ValueKey('albums-loading-spinner'),
                        dimension: 18,
                        child: FCircularProgress(),
                      ),
                    ),
                  ),
                ]
              : albumGroups.isEmpty
              ? [
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
                  ),
                ]
              : albumGroups,
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
