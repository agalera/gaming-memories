import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/library.dart';
import 'thumbnail_service.dart';
import 'video_metadata_service.dart';

typedef FolderListingCallback = void Function(FolderListing listing);

class LibraryScanner {
  const LibraryScanner({
    this.thumbnailService = const ThumbnailService(),
    this.videoMetadataService = const VideoMetadataService(),
  });

  final ThumbnailService thumbnailService;
  final VideoMetadataService videoMetadataService;

  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
  static const _videoExtensions = {'.mp4', '.avi', '.mkv', '.webm'};
  static final _datePattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})',
  );
  static final _compactDatePattern = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})',
  );

  Future<MediaLibrary> scan(String outputPath) async {
    if (outputPath.trim().isEmpty) {
      return const MediaLibrary.empty();
    }

    final root = Directory(expandUserPath(outputPath.trim()));
    if (!await root.exists()) {
      return const MediaLibrary.empty();
    }

    final albums = <GameAlbum>[];
    final platformDirectories = await _directories(root);

    for (final platformDirectory in platformDirectories) {
      final gameDirectories = await _directories(platformDirectory);
      for (final gameDirectory in gameDirectories) {
        final platform = p.basename(platformDirectory.path);
        final game = p.basename(gameDirectory.path);
        final media = await _mediaFiles(gameDirectory, platform, game, '');
        final subAlbums = <SubAlbum>[];
        for (final child in await _directories(gameDirectory)) {
          final subAlbum = await _subAlbum(
            child,
            gameDirectory,
            platform,
            game,
          );
          if (subAlbum != null) {
            subAlbums.add(subAlbum);
          }
        }

        if (media.isNotEmpty || subAlbums.isNotEmpty) {
          albums.add(
            GameAlbum(
              platform: platform,
              game: game,
              media: media,
              subAlbums: subAlbums,
            ),
          );
        }
      }
    }

    albums.sort((left, right) {
      final platformOrder = left.platform.compareTo(right.platform);
      return platformOrder == 0
          ? left.game.compareTo(right.game)
          : platformOrder;
    });

    return MediaLibrary(albums: albums);
  }

  Future<List<LibraryFolder>> folderTree(String outputPath) async {
    if (outputPath.trim().isEmpty) {
      return const [];
    }

    final root = Directory(expandUserPath(outputPath.trim()));
    if (!await root.exists()) {
      return const [];
    }

    final platforms = <LibraryFolder>[];
    for (final platformDirectory in await _directories(root)) {
      final games = <LibraryFolder>[];
      for (final gameDirectory in await _directories(platformDirectory)) {
        games.add(
          LibraryFolder(
            name: p.basename(gameDirectory.path),
            path: gameDirectory.path,
            relativePath: p.basename(gameDirectory.path),
            coverPath: await _coverPath(gameDirectory),
            childrenLoaded: false,
          ),
        );
      }
      platforms.add(
        LibraryFolder(
          name: p.basename(platformDirectory.path),
          path: platformDirectory.path,
          children: games,
        ),
      );
    }
    return platforms;
  }

  Future<List<LibraryFolder>> subAlbumTree(
    String outputPath,
    String platform,
    String game,
  ) async {
    if (outputPath.trim().isEmpty) {
      return const [];
    }

    final rootPath = p.normalize(p.absolute(expandUserPath(outputPath.trim())));
    final gameDirectory = Directory(p.join(rootPath, platform, game));
    final normalizedGame = p.normalize(p.absolute(gameDirectory.path));
    if (!p.isWithin(rootPath, normalizedGame) ||
        !await gameDirectory.exists()) {
      return const [];
    }

    final folders = <LibraryFolder>[];
    for (final directory in await _directories(gameDirectory)) {
      folders.add(await _subAlbumFolderNode(directory, gameDirectory));
    }
    return folders;
  }

  Future<FolderListing> folderContents(
    String outputPath,
    String platform,
    String game, {
    String subAlbumPath = '',
    FolderListingCallback? onUpdate,
  }) async {
    if (outputPath.trim().isEmpty) {
      return const FolderListing.empty();
    }

    final rootPath = p.normalize(p.absolute(expandUserPath(outputPath.trim())));
    final gameDirectory = Directory(p.join(rootPath, platform, game));
    final directory = subAlbumPath.isEmpty
        ? gameDirectory
        : Directory(p.join(gameDirectory.path, subAlbumPath));
    final normalizedGame = p.normalize(p.absolute(gameDirectory.path));
    final normalizedDirectory = p.normalize(p.absolute(directory.path));
    if (!p.isWithin(rootPath, normalizedGame) ||
        (normalizedDirectory != normalizedGame &&
            !p.isWithin(normalizedGame, normalizedDirectory))) {
      return const FolderListing.empty();
    }
    if (!await directory.exists()) {
      return const FolderListing.empty();
    }

    final folders = <LibraryFolder>[];
    final media = <MediaItem>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Directory) {
          folders.add(
            LibraryFolder(
              name: p.basename(entity.path),
              path: entity.path,
              relativePath: p.relative(entity.path, from: gameDirectory.path),
            ),
          );
        } else if (entity is File &&
            _isMedia(entity.path) &&
            !_isThumbnail(entity.path) &&
            !_isCover(entity.path)) {
          try {
            media.add(
              await _listedMediaItem(entity, platform, game, subAlbumPath),
            );
          } on FileSystemException {
            continue;
          }
          if (media.length % 32 == 0) {
            onUpdate?.call(_folderListing(folders, media));
          }
        }
      }
    } on FileSystemException {
      return _folderListing(folders, media);
    }

    return _folderListing(folders, media);
  }

  Future<FolderListing> prepareFolderContents(
    FolderListing listing, {
    FolderListingCallback? onUpdate,
    bool Function()? isCancelled,
  }) async {
    final media = List<MediaItem>.of(listing.media);
    for (var index = 0; index < media.length; index++) {
      if (isCancelled?.call() ?? false) {
        break;
      }
      final item = media[index];
      media[index] = await prepareMediaItem(item) ?? item;

      if ((index + 1) % 16 == 0 || index == media.length - 1) {
        onUpdate?.call(
          FolderListing(
            folders: listing.folders,
            media: List.unmodifiable(media),
          ),
        );
      }
    }
    return FolderListing(
      folders: listing.folders,
      media: List.unmodifiable(media),
    );
  }

  Future<MediaItem?> prepareMediaItem(MediaItem item) async {
    try {
      final source = item.file;
      final stat = await source.stat();
      final thumbnailPath = item.isVideo
          ? await thumbnailService.ensureVideoThumbnail(source, stat)
          : await thumbnailService.ensureImageThumbnail(source, stat);
      final duration = item.isVideo
          ? await videoMetadataService.ensureDuration(source, stat)
          : null;
      return MediaItem(
        path: item.path,
        platform: item.platform,
        game: item.game,
        capturedAt: item.capturedAt,
        kind: item.kind,
        subAlbumPath: item.subAlbumPath,
        thumbnailPath: thumbnailPath,
        duration: duration,
        sourceModifiedAt: stat.modified,
        sourceSize: stat.size,
      );
    } on FileSystemException {
      return null;
    }
  }

  /// Reads and prepares one known media path without rescanning its parent.
  Future<MediaItem?> mediaItemAt(String outputPath, String path) async {
    if (outputPath.trim().isEmpty) {
      return null;
    }

    final root = p.normalize(p.absolute(expandUserPath(outputPath.trim())));
    final normalized = p.normalize(p.absolute(path));
    if (!p.isWithin(root, normalized) ||
        !_isMedia(normalized) ||
        _isThumbnail(normalized) ||
        _isCover(normalized)) {
      return null;
    }
    final relative = p.relative(normalized, from: root);
    final parts = p.split(relative);
    if (parts.length < 3 || parts.first == '..') {
      return null;
    }

    final file = File(normalized);
    if (!await file.exists()) {
      return null;
    }
    try {
      final item = await _listedMediaItem(
        file,
        parts[0],
        parts[1],
        parts.length == 3
            ? ''
            : p.joinAll(parts.skip(2).take(parts.length - 3)),
      );
      return await prepareMediaItem(item);
    } on FileSystemException {
      return null;
    }
  }

  Future<List<MediaItem>> mediaTree(
    String outputPath,
    String platform,
    String game, {
    String subAlbumPath = '',
  }) async {
    if (outputPath.trim().isEmpty) {
      return const [];
    }

    final rootPath = p.normalize(p.absolute(expandUserPath(outputPath.trim())));
    final gamePath = p.join(rootPath, platform, game);
    final directoryPath = subAlbumPath.isEmpty
        ? gamePath
        : p.join(gamePath, subAlbumPath);
    final normalizedGame = p.normalize(p.absolute(gamePath));
    final normalizedDirectory = p.normalize(p.absolute(directoryPath));
    if (!p.isWithin(rootPath, normalizedGame) ||
        (normalizedDirectory != normalizedGame &&
            !p.isWithin(normalizedGame, normalizedDirectory))) {
      return const [];
    }

    return _mediaTree(
      Directory(normalizedDirectory),
      Directory(normalizedGame),
      platform,
      game,
    );
  }

  bool supportsMediaPath(String path) => _isMedia(path);

  bool isCoverPath(String path) => _isCover(path);

  Future<MediaItem> _listedMediaItem(
    File file,
    String platform,
    String game,
    String subAlbumPath,
  ) async {
    final stat = await file.stat();
    final capturedAt = _dateFromName(file.path) ?? stat.modified;
    final isVideo = _isVideo(file.path);
    return MediaItem(
      path: file.path,
      platform: platform,
      game: game,
      capturedAt: capturedAt,
      kind: isVideo ? MediaKind.video : MediaKind.image,
      subAlbumPath: subAlbumPath,
      thumbnailPath: thumbnailService.pathFor(file.path),
      sourceModifiedAt: stat.modified,
      sourceSize: stat.size,
    );
  }

  FolderListing _folderListing(
    List<LibraryFolder> folders,
    List<MediaItem> media,
  ) {
    final sortedFolders = List<LibraryFolder>.of(folders)
      ..sort((left, right) => left.name.compareTo(right.name));
    final sortedMedia = List<MediaItem>.of(media)
      ..sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return FolderListing(
      folders: List.unmodifiable(sortedFolders),
      media: List.unmodifiable(sortedMedia),
    );
  }

  Future<LibraryFolder> _subAlbumFolderNode(
    Directory directory,
    Directory gameDirectory,
  ) async {
    final children = <LibraryFolder>[];
    for (final child in await _directories(directory)) {
      children.add(await _subAlbumFolderNode(child, gameDirectory));
    }

    final relativePath = p.relative(directory.path, from: gameDirectory.path);
    return LibraryFolder(
      name: p.basename(directory.path),
      path: directory.path,
      relativePath: relativePath,
      children: children,
    );
  }

  Future<String?> _coverPath(Directory directory) async {
    for (final extension in _imageExtensions) {
      final file = File(p.join(directory.path, 'cover$extension'));
      if (await file.exists()) {
        return file.path;
      }
    }
    return null;
  }

  Future<List<Directory>> _directories(Directory parent) async {
    try {
      final directories = await parent
          .list(followLinks: false)
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();
      directories.sort((left, right) => left.path.compareTo(right.path));
      return directories;
    } on FileSystemException {
      return const [];
    }
  }

  Future<SubAlbum?> _subAlbum(
    Directory directory,
    Directory gameDirectory,
    String platform,
    String game,
  ) async {
    final relativePath = p.relative(directory.path, from: gameDirectory.path);
    final media = await _mediaFiles(directory, platform, game, relativePath);
    final children = <SubAlbum>[];

    for (final child in await _directories(directory)) {
      final subAlbum = await _subAlbum(child, gameDirectory, platform, game);
      if (subAlbum != null) {
        children.add(subAlbum);
      }
    }

    if (media.isEmpty && children.isEmpty) {
      return null;
    }

    return SubAlbum(
      name: p.basename(directory.path),
      relativePath: relativePath,
      media: media,
      children: children,
    );
  }

  Future<List<MediaItem>> _mediaTree(
    Directory directory,
    Directory gameDirectory,
    String platform,
    String game,
  ) async {
    if (!await directory.exists()) {
      return const [];
    }

    final relativePath = p.relative(directory.path, from: gameDirectory.path);
    final media = await _mediaFiles(
      directory,
      platform,
      game,
      relativePath == '.' ? '' : relativePath,
    );
    for (final child in await _directories(directory)) {
      media.addAll(await _mediaTree(child, gameDirectory, platform, game));
    }
    media.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return media;
  }

  Future<List<MediaItem>> _mediaFiles(
    Directory directory,
    String platform,
    String game,
    String subAlbumPath,
  ) async {
    final media = <MediaItem>[];

    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File ||
            !_isMedia(entity.path) ||
            _isThumbnail(entity.path) ||
            _isCover(entity.path)) {
          continue;
        }

        final stat = await entity.stat();
        final isVideo = _isVideo(entity.path);
        final thumbnailPath = isVideo
            ? await thumbnailService.ensureVideoThumbnail(entity, stat)
            : await thumbnailService.ensureImageThumbnail(entity, stat);
        final duration = isVideo
            ? await videoMetadataService.ensureDuration(entity, stat)
            : null;
        media.add(
          MediaItem(
            path: entity.path,
            platform: platform,
            game: game,
            capturedAt: _dateFromName(entity.path) ?? stat.modified,
            kind: isVideo ? MediaKind.video : MediaKind.image,
            subAlbumPath: subAlbumPath,
            thumbnailPath: thumbnailPath,
            duration: duration,
            sourceModifiedAt: stat.modified,
            sourceSize: stat.size,
          ),
        );
      }
    } on FileSystemException {
      return media;
    }

    media.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return media;
  }

  bool _isMedia(String path) {
    final extension = p.extension(path).toLowerCase();
    return _imageExtensions.contains(extension) ||
        _videoExtensions.contains(extension);
  }

  bool _isVideo(String path) {
    return _videoExtensions.contains(p.extension(path).toLowerCase());
  }

  bool _isThumbnail(String path) {
    return p.basename(path).toLowerCase().endsWith('.thumb.jpg');
  }

  bool _isCover(String path) {
    return p.basenameWithoutExtension(path).toLowerCase() == 'cover';
  }

  DateTime? _dateFromName(String path) {
    final name = p.basename(path);
    final match =
        _datePattern.firstMatch(name) ?? _compactDatePattern.firstMatch(name);
    if (match == null) {
      return null;
    }

    try {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } on FormatException {
      return null;
    }
  }
}

String expandUserPath(String path) {
  if (path == '~') {
    return homeDirectory() ?? path;
  }

  if (path.startsWith('~/') || path.startsWith(r'~\')) {
    final home = homeDirectory();
    if (home != null) {
      return p.join(home, path.substring(2));
    }
  }

  return path;
}

String? homeDirectory() {
  return Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
}
