import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/library.dart';
import 'screenshot_actions.dart';

class ScreenshotGallery extends StatelessWidget {
  const ScreenshotGallery({
    required this.screenshots,
    required this.description,
    required this.needsSetup,
    required this.onSetup,
    required this.controller,
    super.key,
  });

  final List<ScreenshotItem> screenshots;
  final String description;
  final bool needsSetup;
  final VoidCallback onSetup;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    if (screenshots.isEmpty) {
      return _EmptyGallery(needsSetup: needsSetup, onSetup: onSetup);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  description,
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ),
              FBadge(
                variant: FBadgeVariant.secondary,
                child: Text('${screenshots.length} screenshots'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 320).floor().clamp(
                  1,
                  5,
                );

                return GridView.builder(
                  itemCount: screenshots.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 245,
                  ),
                  itemBuilder: (context, index) => _ScreenshotCard(
                    screenshot: screenshots[index],
                    controller: controller,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotCard extends StatelessWidget {
  const _ScreenshotCard({required this.screenshot, required this.controller});

  final ScreenshotItem screenshot;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return ScreenshotContextMenu(
      controller: controller,
      screenshot: screenshot,
      child: FTappable(
        key: ValueKey('screenshot-card-${screenshot.path}'),
        semanticsLabel: 'Open ${screenshot.game} screenshot',
        onPress: () => controller.showScreenshot(screenshot),
        child: FCard(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: Image.file(
                    screenshot.galleryFile,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        screenshot.thumbnailPath == null
                        ? _imageError(context)
                        : Image.file(
                            screenshot.file,
                            fit: BoxFit.cover,
                            cacheWidth: 900,
                            errorBuilder: (context, error, stackTrace) =>
                                _imageError(context),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      screenshot.game,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.body.sm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${screenshot.platform}  •  ${_formatDate(screenshot.capturedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.body.xs.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageError(BuildContext context) {
    return ColoredBox(
      color: context.theme.colors.muted,
      child: Center(
        child: Icon(
          FLucideIcons.imageOff,
          color: context.theme.colors.mutedForeground,
        ),
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery({required this.needsSetup, required this.onSetup});

  final bool needsSetup;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.theme.colors.muted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  FLucideIcons.images,
                  color: context.theme.colors.mutedForeground,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                needsSetup
                    ? 'Choose your library folder'
                    : 'No screenshots yet',
                style: context.theme.typography.display.xl.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                needsSetup
                    ? 'Set a library folder and enable Diablo IV to create your first album.'
                    : 'Collect screenshots to add new memories to this view.',
                style: context.theme.typography.body.sm.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
              if (needsSetup) ...[
                const SizedBox(height: 20),
                FButton(
                  mainAxisSize: MainAxisSize.min,
                  prefix: const Icon(FLucideIcons.settings),
                  onPress: onSetup,
                  child: const Text('Open settings'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}  '
      '${two(value.hour)}:${two(value.minute)}';
}
