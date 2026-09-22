import 'package:path/path.dart' as p;

export '../capture_date.dart' show capturedAtFromName;

enum GalleryFileKind { image, video }

/// One capture in the rendered gallery, with the sidecars the page needs.
class GalleryFile {
  const GalleryFile({
    required this.name,
    required this.sourcePath,
    required this.kind,
    required this.modified,
    required this.size,
    required this.capturedAt,
    this.thumbnailPath,
    this.duration,
  });

  /// The file name on disk, which is also the last segment of its link.
  final String name;

  /// The capture's absolute path in the library folder.
  final String sourcePath;
  final GalleryFileKind kind;
  final DateTime modified;

  /// When the capture was taken, from its name when it carries one and from
  /// its modification time otherwise — the same reading the app's own library
  /// makes of it.
  final DateTime capturedAt;
  final int size;

  /// The `<name>.thumb.jpg` beside it, when one has been generated. A file
  /// without one still renders; the browser falls back to the capture itself.
  final String? thumbnailPath;

  /// Read from the `<name>.metadata.json` sidecar, so publishing never has to
  /// probe a clip itself.
  final Duration? duration;

  bool get isVideo => kind == GalleryFileKind.video;

  String get thumbnailName => '$name.thumb.jpg';

  /// `1:05` from a minute, `42s` below one, and nothing without a duration.
  String get formattedDuration {
    final value = duration;
    if (value == null || value.inSeconds <= 0) {
      return '';
    }
    if (value.inSeconds < 60) {
      return '${value.inSeconds}s';
    }
    final seconds = value.inSeconds % 60;
    return '${value.inMinutes}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Where a folder's tile image comes from. A library cover is a file beside
/// the album; a bundled one ships with the app and is written into the build
/// directory at publish time, because nothing puts a cover in a platform
/// folder.
enum GalleryCoverOrigin { library, bundled }

class GalleryCover {
  const GalleryCover.fromLibrary({required this.name, required this.source})
    : origin = GalleryCoverOrigin.library;

  const GalleryCover.bundled({required this.name, required this.source})
    : origin = GalleryCoverOrigin.bundled;

  /// The file name the cover is published under, as `cover.png`.
  final String name;

  /// An absolute path in the library, or an asset key, by [origin].
  final String source;
  final GalleryCoverOrigin origin;

  bool get isBundled => origin == GalleryCoverOrigin.bundled;
}

/// One album page of the rendered gallery. The root node is the library
/// folder itself and carries an empty [relativePath].
class GalleryFolder {
  const GalleryFolder({
    required this.name,
    required this.relativePath,
    required this.folders,
    required this.files,
    required this.lastUpdated,
    this.cover,
  });

  final String name;

  /// The path below the library folder, in `/` segments, as `Steam/Hades`.
  final String relativePath;
  final List<GalleryFolder> folders;
  final List<GalleryFile> files;

  /// The newest capture below this folder, which the page footer shows.
  final DateTime lastUpdated;

  /// The tile image for this folder, when it has one.
  final GalleryCover? cover;

  bool get isRoot => relativePath.isEmpty;

  /// A folder holding neither captures nor sub-albums is not linked to.
  bool get isEmpty => folders.isEmpty && files.isEmpty;

  /// Only this folder's own captures, as the tile counts on a parent page
  /// report them.
  int get imageCount => files.where((file) => !file.isVideo).length;

  int get videoCount => files.where((file) => file.isVideo).length;

  /// The absolute link to this folder, percent-encoded segment by segment and
  /// closed with a slash so a server reads it as a directory.
  String get webPath {
    if (relativePath.isEmpty) {
      return '/';
    }
    final segments = relativePath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent);
    return '/${segments.join('/')}/';
  }

  /// The tile image on a parent page: the album's own cover when it has one,
  /// and otherwise the thumbnail of the first capture found below it, so an
  /// album without a cover is not a broken image.
  String? get coverWebPath {
    final own = cover;
    if (own != null) {
      return '$webPath${Uri.encodeComponent(own.name)}';
    }
    return _firstThumbnailWebPath();
  }

  /// Where the cover is published, relative to the site root.
  String? get coverRelativePath {
    final own = cover;
    if (own == null) {
      return null;
    }
    return relativePath.isEmpty ? own.name : '$relativePath/${own.name}';
  }

  String? _firstThumbnailWebPath() {
    for (final file in files) {
      if (file.thumbnailPath != null) {
        return fileWebPath(file.thumbnailName);
      }
    }
    for (final folder in folders) {
      final found = folder._firstThumbnailWebPath();
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  String fileWebPath(String fileName) =>
      '$webPath${Uri.encodeComponent(fileName)}';

  /// Every page of the tree, this folder's first. A page carries the trail of
  /// ancestors it draws as breadcrumbs, root first and itself last.
  Iterable<GalleryPage> pages([
    List<GalleryFolder> ancestors = const [],
  ]) sync* {
    final trail = [...ancestors, this];
    yield GalleryPage(folder: this, trail: trail);
    for (final folder in folders) {
      yield* folder.pages(trail);
    }
  }
}

/// One rendered `index.html`: the folder it shows and the trail that leads to
/// it.
class GalleryPage {
  const GalleryPage({required this.folder, required this.trail});

  final GalleryFolder folder;
  final List<GalleryFolder> trail;

  /// Where the page is written, relative to the site root.
  String get relativePath =>
      folder.isRoot ? 'index.html' : '${folder.relativePath}/index.html';
}

/// The extensions the library scanner collects, which is what the gallery can
/// show. Anything else in the library folder is left out of the site.
GalleryFileKind? galleryFileKind(String fileName) {
  final extension = p.extension(fileName).toLowerCase();
  return switch (extension) {
    '.jpg' || '.jpeg' || '.png' || '.webp' => GalleryFileKind.image,
    '.mp4' || '.avi' || '.mkv' || '.webm' => GalleryFileKind.video,
    _ => null,
  };
}
