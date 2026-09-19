import 'dart:io';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../controllers/library_controller.dart';
import '../models/library.dart';
import '../widgets/screenshot_actions.dart';

class ScreenshotDetailPage extends StatelessWidget {
  const ScreenshotDetailPage({
    required this.screenshot,
    required this.controller,
    super.key,
  });

  final ScreenshotItem screenshot;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final image = _FullImage(screenshot: screenshot);
          final details = _ScreenshotDetails(
            screenshot: screenshot,
            controller: controller,
          );

          if (constraints.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: image),
                const SizedBox(width: 20),
                SizedBox(width: 320, child: details),
              ],
            );
          }

          return ListView(
            children: [
              SizedBox(height: constraints.maxHeight * 0.62, child: image),
              const SizedBox(height: 16),
              details,
            ],
          );
        },
      ),
    );
  }
}

class _FullImage extends StatelessWidget {
  const _FullImage({required this.screenshot});

  final ScreenshotItem screenshot;

  @override
  Widget build(BuildContext context) {
    return FCard(
      clipBehavior: Clip.antiAlias,
      child: ColoredBox(
        color: context.theme.colors.muted,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Center(
              child: Image.file(
                screenshot.file,
                key: const ValueKey('screenshot-detail-image'),
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
    );
  }
}

class _ScreenshotDetails extends StatelessWidget {
  const _ScreenshotDetails({
    required this.screenshot,
    required this.controller,
  });

  final ScreenshotItem screenshot;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final extension = p.extension(screenshot.path);

    return FCard(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Screenshot details',
              style: context.theme.typography.display.lg.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ScreenshotActionButtons(
              controller: controller,
              screenshot: screenshot,
            ),
            const SizedBox(height: 20),
            _DetailItem(label: 'Game', value: screenshot.game),
            _DetailItem(label: 'Platform', value: screenshot.platform),
            _DetailItem(
              label: 'Captured',
              value: _formatDate(screenshot.capturedAt),
            ),
            _DetailItem(label: 'File name', value: p.basename(screenshot.path)),
            _DetailItem(
              label: 'File type',
              value: extension.isEmpty
                  ? 'Unknown'
                  : extension.substring(1).toUpperCase(),
            ),
            FutureBuilder<FileStat>(
              future: screenshot.file.stat(),
              builder: (context, snapshot) => _DetailItem(
                label: 'File size',
                value: snapshot.hasData
                    ? _formatBytes(snapshot.data!.size)
                    : 'Unavailable',
              ),
            ),
            _DetailItem(
              label: 'Path',
              value: screenshot.path,
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
