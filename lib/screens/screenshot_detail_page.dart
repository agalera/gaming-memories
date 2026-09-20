import 'dart:io';

import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../models/library.dart';

class MediaDetailPage extends StatelessWidget {
  const MediaDetailPage({required this.media, super.key});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final preview = _MediaPreview(media: media);
          final details = _MediaDetails(media: media);

          if (constraints.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: preview),
                const SizedBox(width: 20),
                SizedBox(width: 320, child: details),
              ],
            );
          }

          return ListView(
            children: [
              SizedBox(height: constraints.maxHeight * 0.62, child: preview),
              const SizedBox(height: 16),
              details,
            ],
          );
        },
      ),
    );
  }
}

class _MediaPreview extends StatefulWidget {
  const _MediaPreview({required this.media});

  final MediaItem media;

  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 0.5;
  static const double _maxScale = 5;
  static const double _doubleTapScale = 2.5;

  final TransformationController _transformation = TransformationController();
  late final AnimationController _zoomAnimation;
  Animation<Matrix4>? _zoomTween;
  Offset _doubleTapFocalPoint = Offset.zero;
  bool _zoomModifierHeld = false;

  @override
  void initState() {
    super.initState();
    _zoomAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(_applyZoomAnimation);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didUpdateWidget(covariant _MediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.path != widget.media.path) {
      _resetZoom();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _zoomAnimation.dispose();
    _transformation.dispose();
    super.dispose();
  }

  // Trackpad scroll pans by default, and zooms while the macOS zoom modifier
  // is held, which is how Preview and Photos behave.
  bool _handleKeyEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final held = keyboard.isMetaPressed || keyboard.isControlPressed;
    if (held != _zoomModifierHeld && mounted) {
      setState(() => _zoomModifierHeld = held);
    }
    return false;
  }

  void _applyZoomAnimation() {
    final tween = _zoomTween;
    if (tween != null) {
      _transformation.value = tween.value;
    }
  }

  void _resetZoom() {
    _zoomAnimation.stop();
    _zoomTween = null;
    _transformation.value = Matrix4.identity();
  }

  void _animateTo(Matrix4 target) {
    _zoomTween = Matrix4Tween(
      begin: _transformation.value,
      end: target,
    ).animate(CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOut));
    _zoomAnimation.forward(from: 0);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapFocalPoint = details.localPosition;
  }

  void _handleDoubleTap(Size viewport) {
    if (_transformation.value.getMaxScaleOnAxis() > 1.01) {
      _animateTo(Matrix4.identity());
      return;
    }

    _animateTo(_zoomedAt(_doubleTapFocalPoint, viewport));
  }

  // Scales around the tapped point, keeping the image inside the viewport so
  // the result matches what InteractiveViewer allows when panning.
  Matrix4 _zoomedAt(Offset focalPoint, Size viewport) {
    final x = (focalPoint.dx * (1 - _doubleTapScale)).clamp(
      viewport.width * (1 - _doubleTapScale),
      0.0,
    );
    final y = (focalPoint.dy * (1 - _doubleTapScale)).clamp(
      viewport.height * (1 - _doubleTapScale),
      0.0,
    );

    return Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return FCard(
      clipBehavior: Clip.antiAlias,
      child: ColoredBox(
        color: context.theme.colors.muted,
        child: widget.media.isVideo
            ? _VideoPreview(media: widget.media)
            : Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    onDoubleTapDown: _handleDoubleTapDown,
                    onDoubleTap: () => _handleDoubleTap(constraints.biggest),
                    child: InteractiveViewer(
                      key: const ValueKey('media-detail-viewer'),
                      transformationController: _transformation,
                      trackpadScrollCausesScale: _zoomModifierHeld,
                      minScale: _minScale,
                      maxScale: _maxScale,
                      child: Center(
                        child: Image.file(
                          widget.media.file,
                          key: const ValueKey('media-detail-image'),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(
                              FLucideIcons.imageOff,
                              size: 44,
                              color: context.theme.colors.mutedForeground,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.media});

  final MediaItem media;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late final Player _player;
  late final VideoController _videoController;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _player.open(Media(widget.media.path), play: false);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Video(
      key: const ValueKey('media-detail-video'),
      controller: _videoController,
      fit: BoxFit.contain,
    );
  }
}

class _MediaDetails extends StatelessWidget {
  const _MediaDetails({required this.media});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    final extension = p.extension(media.path);

    return FCard(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              media.isVideo ? 'Video details' : 'Image details',
              style: context.theme.typography.display.lg.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            _DetailItem(label: 'Game', value: media.game),
            _DetailItem(label: 'Platform', value: media.platform),
            if (media.subAlbumPath.isNotEmpty)
              _DetailItem(label: 'Sub-album', value: media.subAlbumPath),
            _DetailItem(
              label: 'Captured',
              value: _formatDate(media.capturedAt),
            ),
            if (media.duration != null)
              _DetailItem(
                label: 'Duration',
                value: _formatDuration(media.duration!),
              ),
            _DetailItem(label: 'File name', value: p.basename(media.path)),
            _DetailItem(
              label: 'File type',
              value: extension.isEmpty
                  ? 'Unknown'
                  : extension.substring(1).toUpperCase(),
            ),
            FutureBuilder<FileStat>(
              future: media.file.stat(),
              builder: (context, snapshot) => _DetailItem(
                label: 'File size',
                value: snapshot.hasData
                    ? _formatBytes(snapshot.data!.size)
                    : 'Unavailable',
              ),
            ),
            _DetailItem(
              label: 'Path',
              value: media.path,
              selectable: true,
              last: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.label,
    required this.value,
    this.selectable = false,
    this.last = false,
  });

  final String label;
  final String value;
  final bool selectable;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      value,
      style: context.theme.typography.body.sm,
      softWrap: true,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.theme.typography.body.xs.copyWith(
              color: context.theme.colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (selectable) SelectionArea(child: text) else text,
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}  '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }

  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) {
    return '${kilobytes.toStringAsFixed(1)} KB';
  }

  final megabytes = kilobytes / 1024;
  if (megabytes < 1024) {
    return '${megabytes.toStringAsFixed(1)} MB';
  }

  return '${(megabytes / 1024).toStringAsFixed(1)} GB';
}

String _formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
