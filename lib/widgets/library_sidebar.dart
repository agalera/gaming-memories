import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/library.dart';

class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({required this.controller, super.key});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final albumGroups = controller.library.albumsByPlatform.entries.map((
      entry,
    ) {
      return _PlatformSidebarItem(
        key: ValueKey('platform-${entry.key}'),
        platform: entry.key,
        selected:
            controller.view == LibraryView.platform &&
            controller.selectedPlatform == entry.key,
        onPress: () => controller.showPlatform(entry.key),
        children: entry.value.map((album) {
          final selected =
              controller.view == LibraryView.album &&
              controller.selectedPlatform == album.platform &&
              controller.selectedGame == album.game;

          return _AlbumSidebarItem(
            key: ValueKey('game-${album.platform}-${album.game}'),
            itemKey: 'game-${album.platform}-${album.game}',
            name: album.game,
            count: album.allMedia.length,
            icon: FLucideIcons.gamepad2,
            selected: selected,
            onPress: () => controller.showAlbum(album.platform, album.game),
            children: album.subAlbums
                .map(
                  (subAlbum) =>
                      _subAlbumItem(album.platform, album.game, subAlbum),
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
      footer: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FButton(
          key: const ValueKey('settings-sidebar-button'),
          variant: FButtonVariant.ghost,
          selected: controller.view == LibraryView.settings,
          mainAxisSize: MainAxisSize.max,
          prefix: const Icon(FLucideIcons.settings),
          onPress: controller.showSettings,
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Text('Settings'),
          ),
        ),
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
          children: albumGroups.isEmpty
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

  Widget _subAlbumItem(String platform, String game, SubAlbum subAlbum) {
    return _AlbumSidebarItem(
      key: ValueKey('sub-album-$platform-$game-${subAlbum.relativePath}'),
      itemKey: 'sub-album-$platform-$game-${subAlbum.relativePath}',
      name: subAlbum.name,
      count: subAlbum.allMedia.length,
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
    required this.count,
    required this.icon,
    required this.selected,
    required this.onPress,
    required this.children,
    super.key,
  });

  final String itemKey;
  final String name;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onPress;
  final List<Widget> children;

  @override
  State<_AlbumSidebarItem> createState() => _AlbumSidebarItemState();
}

class _AlbumSidebarItemState extends State<_AlbumSidebarItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final label = '${widget.name}  ${widget.count}';

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
                  child: Text(label, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            if (widget.children.isNotEmpty) ...[
              const SizedBox(width: 2),
              FButton.icon(
                key: ValueKey('${widget.itemKey}-toggle'),
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                selected: widget.selected,
                semanticsLabel: _expanded
                    ? 'Collapse ${widget.name} sub-albums'
                    : 'Expand ${widget.name} sub-albums',
                onPress: () => setState(() => _expanded = !_expanded),
                child: AnimatedRotation(
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
