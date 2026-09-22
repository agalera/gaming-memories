import 'dart:io';

import 'package:path/path.dart' as p;

import 'gallery_node.dart';

/// Which of the two local trees a published file comes from. The transports
/// need it because rsync copies each root in its own pass.
enum PublishSourceRoot { library, build }

/// One file the remote is meant to hold, and where it comes from locally.
class PublishFile {
  const PublishFile({
    required this.remotePath,
    required this.localPath,
    required this.root,
    required this.size,
    required this.modified,
  });

  /// The path below the remote root, in `/` segments and never leading with
  /// one, as `Steam/Hades/shot.png`.
  final String remotePath;
  final String localPath;
  final PublishSourceRoot root;
  final int size;
  final DateTime modified;
}

/// The whole remote tree: every file it should hold and every directory those
/// files need. Both transports work from this, so they agree on the result.
class PublishPlan {
  const PublishPlan({
    required this.files,
    required this.directories,
    this.excludedAlbums = const [],
  });

  final List<PublishFile> files;

  /// Remote directories, parents before children, so they can be created in
  /// order.
  final List<String> directories;

  /// The album paths left out of the site. rsync needs them as its own
  /// exclusions, because it walks the library folder itself rather than this
  /// list of files.
  final List<String> excludedAlbums;

  int get totalBytes => files.fold(0, (sum, file) => sum + file.size);

  /// Every remote path the plan covers, which is what a mirroring transport
  /// keeps and deletes around.
  Set<String> get remotePaths => {for (final file in files) file.remotePath};
}

/// Merges the rendered pages in the build directory with the captures in the
/// library into the one tree that is uploaded.
class PublishPlanner {
  const PublishPlanner();

  PublishPlan plan({
    required GalleryFolder root,
    required String buildPath,
    Set<String> renderedFiles = const {},
    List<String> excludedAlbums = const [],
  }) {
    final files = <PublishFile>[];
    final directories = <String>{};

    // A file whose render failed is left out rather than published as a
    // stale copy of itself. An empty set means the caller is not filtering.
    bool rendered(String path) =>
        renderedFiles.isEmpty || renderedFiles.contains(path);

    for (final page in root.pages()) {
      final folder = page.folder;
      if (folder.relativePath.isNotEmpty) {
        directories.add(folder.relativePath);
      }

      if (rendered(page.relativePath)) {
        files.add(
          _fromDisk(
            remotePath: page.relativePath,
            localPath: p.join(buildPath, _toLocal(page.relativePath)),
            root: PublishSourceRoot.build,
          ),
        );
      }

      final cover = folder.cover;
      final coverPath = folder.coverRelativePath;
      if (cover != null &&
          coverPath != null &&
          (!cover.isBundled || rendered(coverPath))) {
        // A bundled cover was written into the build directory, so it is
        // published from there like a page.
        files.add(
          _fromDisk(
            remotePath: coverPath,
            localPath: cover.isBundled
                ? p.join(buildPath, _toLocal(coverPath))
                : cover.source,
            root: cover.isBundled
                ? PublishSourceRoot.build
                : PublishSourceRoot.library,
          ),
        );
      }

      for (final file in folder.files) {
        files.add(
          PublishFile(
            remotePath: _join(folder.relativePath, file.name),
            localPath: file.sourcePath,
            root: PublishSourceRoot.library,
            size: file.size,
            modified: file.modified,
          ),
        );

        final thumbnail = file.thumbnailPath;
        if (thumbnail != null) {
          files.add(
            _fromDisk(
              remotePath: _join(folder.relativePath, file.thumbnailName),
              localPath: thumbnail,
              root: PublishSourceRoot.library,
            ),
          );
        }
      }
    }

    // Captures before pages, so a page never arrives ahead of the media it
    // links to. A visitor reading the site mid-publish sees the previous
    // pages, which still point at files that are there.
    files.sort((left, right) {
      if (left.root != right.root) {
        return left.root == PublishSourceRoot.library ? -1 : 1;
      }
      return left.remotePath.compareTo(right.remotePath);
    });
    final ordered = directories.toList()
      ..sort((left, right) {
        final depth = left.split('/').length.compareTo(right.split('/').length);
        return depth == 0 ? left.compareTo(right) : depth;
      });

    return PublishPlan(
      files: files,
      directories: ordered,
      excludedAlbums: excludedAlbums,
    );
  }

  static PublishFile _fromDisk({
    required String remotePath,
    required String localPath,
    required PublishSourceRoot root,
  }) {
    final file = File(localPath);
    FileStat? stat;
    try {
      stat = file.statSync();
    } on FileSystemException {
      stat = null;
    }
    return PublishFile(
      remotePath: remotePath,
      localPath: localPath,
      root: root,
      size: stat?.size ?? 0,
      modified: stat?.modified ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static String _join(String folder, String name) =>
      folder.isEmpty ? name : '$folder/$name';

  static String _toLocal(String remotePath) =>
      remotePath.split('/').join(Platform.pathSeparator);
}
