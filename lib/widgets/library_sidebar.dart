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
      return FSidebarItem(
        icon: const Icon(FLucideIcons.monitor),
        label: Text(entry.key),
        selected:
            controller.view == LibraryView.platform &&
            controller.selectedPlatform == entry.key,
        initiallyExpanded: true,
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
          variant: FButtonVariant.ghost,
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
