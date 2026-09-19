import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';

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

          return FSidebarItem(
            icon: const Icon(FLucideIcons.gamepad2),
            label: Text('${album.game}  ${album.screenshots.length}'),
            selected: selected,
            onPress: () => controller.showAlbum(album.platform, album.game),
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
  bool _expanded = true;

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
                child: Text(widget.platform),
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
