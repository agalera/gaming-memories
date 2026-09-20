import 'dart:io';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/library_controller.dart';
import '../models/library.dart';
import 'screenshot_actions.dart';

class MediaGallery extends StatelessWidget {
  const MediaGallery({
    required this.media,
    required this.games,
    required this.folders,
    required this.description,
    required this.isLoading,
    required this.isTimelineRefreshing,
    required this.needsSetup,
    required this.onSetup,
    required this.controller,
    super.key,
  });

  final List<MediaItem> media;
  final List<LibraryFolder> games;
  final List<LibraryFolder> folders;
  final String description;
  final bool isLoading;
  final bool isTimelineRefreshing;
  final bool needsSetup;
  final VoidCallback onSetup;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty && games.isEmpty && folders.isEmpty && !isLoading) {
      return _EmptyGallery(
        needsSetup: needsSetup,
        isTimelineRefreshing: isTimelineRefreshing,
        onSetup: onSetup,
      );
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
              if (isLoading)
                const SizedBox.square(dimension: 18, child: FCircularProgress())
              else if (media.isNotEmpty)
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
                  10,
                );

                return CustomScrollView(
                  key: const ValueKey('media-scroll-view'),
                  slivers: [
                    if (games.isNotEmpty) ...[
                      _sectionTitle(context, 'Games'),
                      SliverToBoxAdapter(
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final game in games)
                              SizedBox(
                                width:
                                    (constraints.maxWidth -
                                        (columns - 1) * 16) /
                                    columns,
                                child: _GameCard(
                                  folder: game,
                                  controller: controller,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (folders.isNotEmpty) ...[
                      _sectionTitle(context, 'Folders', top: games.isNotEmpty),
                      SliverGrid.builder(
                        itemCount: folders.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 96,
                        ),
                        itemBuilder: (context, index) => _FolderCard(
                          folder: folders[index],
                          controller: controller,
                        ),
                      ),
                    ],
                    if (media.isNotEmpty) ...[
                      _sectionTitle(
                        context,
                        'Media',
                        top: games.isNotEmpty || folders.isNotEmpty,
                      ),
                      SliverGrid.builder(
                        itemCount: media.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 245,
                        ),
                        itemBuilder: (context, index) => _MediaCard(
                          media: media[index],
                          controller: controller,
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _sectionTitle(
    BuildContext context,
    String title, {
    bool top = false,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(top: top ? 24 : 0, bottom: 10),
        child: Text(
          title,
          style: context.theme.typography.body.sm.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.folder, required this.controller});

  final LibraryFolder folder;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      key: ValueKey('game-card-${folder.path}'),
      semanticsLabel: 'Open ${folder.name}',
      onPress: () =>
          controller.showAlbum(controller.selectedPlatform!, folder.name),
      child: FCard(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: folder.coverPath == null
                  ? AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _folderPlaceholder(context, FLucideIcons.gamepad2),
                    )
                  : _GameCover(path: folder.coverPath!, itemKey: folder.path),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.theme.typography.body.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCover extends StatefulWidget {
  const _GameCover({required this.path, required this.itemKey});

  final String path;
  final String itemKey;

  @override
  State<_GameCover> createState() => _GameCoverState();
}

class _GameCoverState extends State<_GameCover> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageProvider? _provider;
  double _aspectRatio = 16 / 9;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_GameCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _aspectRatio = 16 / 9;
      _resolve();
    }
  }

  void _resolve() {
    final listener = _listener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }

    final provider = ResizeImage.resizeIfNeeded(
      900,
      null,
      FileImage(File(widget.path)),
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final nextListener = ImageStreamListener((information, synchronousCall) {
      final ratio = information.image.width / information.image.height;
      if (mounted && ratio != _aspectRatio) {
        setState(() => _aspectRatio = ratio);
      }
    });
    _provider = provider;
    _stream = stream;
    _listener = nextListener;
    stream.addListener(nextListener);
  }

  @override
  void dispose() {
    final listener = _listener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _aspectRatio,
      child: Image(
        image: _provider!,
        key: ValueKey('game-cover-${widget.itemKey}'),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _folderPlaceholder(context, FLucideIcons.gamepad2),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.folder, required this.controller});

  final LibraryFolder folder;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      key: ValueKey('folder-card-${folder.path}'),
      semanticsLabel: 'Open ${folder.name}',
      onPress: () => controller.showSubAlbum(
        controller.selectedPlatform!,
        controller.selectedGame!,
        folder.relativePath,
      ),
      child: FCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                FLucideIcons.folder,
                color: context.theme.colors.mutedForeground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(FLucideIcons.chevronRight, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _folderPlaceholder(BuildContext context, IconData icon) {
  return ColoredBox(
    color: context.theme.colors.muted,
    child: Center(
      child: Icon(icon, color: context.theme.colors.mutedForeground, size: 38),
    ),
  );
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
  const _EmptyGallery({
    required this.needsSetup,
    required this.isTimelineRefreshing,
    required this.onSetup,
  });

  final bool needsSetup;
  final bool isTimelineRefreshing;
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
                    : isTimelineRefreshing
                    ? 'Preparing your timeline'
                    : 'No media yet',
                style: context.theme.typography.display.xl.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                needsSetup
                    ? 'Set a library folder and enable Diablo IV to create your first album.'
                    : isTimelineRefreshing
                    ? 'You can browse albums while the timeline cache refreshes.'
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
