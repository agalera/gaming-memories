import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/library.dart';
import 'screenshot_actions.dart';

class MediaGallery extends StatelessWidget {
  const MediaGallery({
    required this.media,
    required this.description,
    required this.needsSetup,
    required this.onSetup,
    required this.controller,
    super.key,
  });

  final List<MediaItem> media;
  final String description;
  final bool needsSetup;
  final VoidCallback onSetup;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
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
                child: Text(
                  '${media.length} ${media.length == 1 ? 'item' : 'items'}',
                ),
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
                  itemCount: media.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 245,
                  ),
                  itemBuilder: (context, index) =>
                      _MediaCard(media: media[index], controller: controller),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.media, required this.controller});

  final MediaItem media;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return MediaContextMenu(
      controller: controller,
      media: media,
      child: FTappable(
        key: ValueKey('media-card-${media.path}'),
        semanticsLabel:
            'Open ${media.game} ${media.isVideo ? 'video' : 'image'}',
        onPress: () => controller.showMedia(media),
        child: FCard(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (media.isVideo && media.thumbnailPath == null)
                        _mediaError(context)
                      else
                        Image.file(
                          media.galleryFile,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              media.thumbnailPath == null || media.isVideo
                              ? _mediaError(context)
                              : Image.file(
                                  media.file,
                                  fit: BoxFit.cover,
                                  cacheWidth: 900,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _mediaError(context),
                                ),
                        ),
                      if (media.isVideo) ...[
                        Center(
                          key: ValueKey('video-indicator-${media.path}'),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xB3000000),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(
                              FLucideIcons.play,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                        ),
                        if (media.duration != null)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xB3000000),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                child: Text(
                                  _formatDuration(media.duration!),
                                  style: context.theme.typography.body.xs
                                      .copyWith(
                                        color: const Color(0xFFFFFFFF),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.game,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.body.sm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${media.platform}  •  ${_formatDate(media.capturedAt)}',
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

  Widget _mediaError(BuildContext context) {
    return ColoredBox(
      color: context.theme.colors.muted,
      child: Center(
        child: Icon(
          media.isVideo ? FLucideIcons.videoOff : FLucideIcons.imageOff,
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
                needsSetup ? 'Choose your library folder' : 'No media yet',
                style: context.theme.typography.display.xl.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                needsSetup
                    ? 'Set a library folder and enable Diablo IV to create your first album.'
                    : 'Collect images and videos to add new memories to this view.',
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

String _formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
