// Renders a gallery from a folder of captures and merges it into one servable
// tree, for looking at the template without publishing anywhere.
//
//   fvm dart run tool/render_demo_gallery.dart <library> <output>
import 'dart:io';

import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/publish/gallery_builder.dart';
import 'package:gaming_memories/services/publish/gallery_renderer.dart';
import 'package:gaming_memories/services/publish/gallery_assets.dart';
import 'package:gaming_memories/services/publish/platform_covers.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: render_demo_gallery <library> <output>');
    exitCode = 64;
    return;
  }

  final library = arguments[0];
  final output = arguments[1];

  final root = await const GalleryBuilder(
    // The bundled covers need a Flutter asset bundle, which a plain script has
    // no access to; a cover.* beside an album still shows.
    platformCovers: NoPlatformCovers(),
  ).build(libraryPath: library, siteTitle: 'Gaming Memories');

  final rendered =
      await const GalleryRenderer(
        platformCovers: NoPlatformCovers(),
        assets: _RepositoryAssets(),
      ).render(
        root: root,
        buildPath: output,
        site: const PublishSiteSettings(
          title: 'Gaming Memories',
          author: '@fmartingr',
          url: 'https://screenshots.example.com',
          footerText:
              "fmartingr's personal screenshot collection, copyright "
              'their respective companies. Be wary of spoilers!',
        ),
      );

  // A real publish uploads the two trees into one; here they are copied into
  // one folder so a plain file server shows what the host would.
  await _copyInto(Directory(library), output);

  stdout.writeln('${rendered.pages.length} pages into $output');
}

Future<void> _copyInto(Directory source, String destination) async {
  await for (final entry in source.list(recursive: true, followLinks: false)) {
    if (entry is! File) {
      continue;
    }
    final name = p.basename(entry.path);
    if (name == 'index.html' ||
        name == '.DS_Store' ||
        name.endsWith('.metadata.json')) {
      continue;
    }
    final target = File(
      p.join(destination, p.relative(entry.path, from: source.path)),
    );
    await target.parent.create(recursive: true);
    await entry.copy(target.path);
  }
}

/// The logo straight from the repository, since a script has no asset bundle.
class _RepositoryAssets implements GalleryAssets {
  const _RepositoryAssets();

  @override
  String? get logoFileName => publishedLogoName;

  @override
  Future<List<int>?> logoBytes() async {
    final file = File(logoAsset);
    return await file.exists() ? file.readAsBytes() : null;
  }
}
