import 'dart:io';

enum MediaKind { image, video }

class MediaItem {
  const MediaItem({
    required this.path,
    required this.platform,
    required this.game,
    required this.capturedAt,
    required this.kind,
    this.subAlbumPath = '',
    this.thumbnailPath,
    this.duration,
  });

  final String path;
  final String platform;
  final String game;
  final DateTime capturedAt;
  final MediaKind kind;
  final String subAlbumPath;
  final String? thumbnailPath;
  final Duration? duration;

  bool get isVideo => kind == MediaKind.video;
  File get file => File(path);
  File get galleryFile => File(thumbnailPath ?? path);
}

class SubAlbum {
  const SubAlbum({
    required this.name,
    required this.relativePath,
    required this.media,
    this.children = const [],
  });

  final String name;
  final String relativePath;
  final List<MediaItem> media;
  final List<SubAlbum> children;

  List<MediaItem> get allMedia {
    final items = [...media, for (final child in children) ...child.allMedia];
    items.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return items;
  }

  SubAlbum? find(String path) {
    if (relativePath == path) {
      return this;
    }

    for (final child in children) {
      final match = child.find(path);
      if (match != null) {
        return match;
      }
    }

    return null;
  }
}

class GameAlbum {
  const GameAlbum({
    required this.platform,
    required this.game,
    required this.media,
    this.subAlbums = const [],
  });

  final String platform;
  final String game;
  final List<MediaItem> media;
  final List<SubAlbum> subAlbums;

  List<MediaItem> get allMedia {
    final items = [
      ...media,
      for (final subAlbum in subAlbums) ...subAlbum.allMedia,
    ];
    items.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return items;
  }

  SubAlbum? subAlbum(String path) {
    for (final child in subAlbums) {
      final match = child.find(path);
      if (match != null) {
        return match;
      }
    }

    return null;
  }
}

class MediaLibrary {
  const MediaLibrary({required this.albums});

  const MediaLibrary.empty() : albums = const [];

  final List<GameAlbum> albums;

  List<MediaItem> get timeline {
    final items = [for (final album in albums) ...album.allMedia];
    items.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return items;
  }

  List<MediaItem> platformTimeline(String platform) {
    final items = [
      for (final album in albums)
        if (album.platform == platform) ...album.allMedia,
    ];
    items.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return items;
  }

  Map<String, List<GameAlbum>> get albumsByPlatform {
    final result = <String, List<GameAlbum>>{};

    for (final album in albums) {
      result.putIfAbsent(album.platform, () => []).add(album);
    }

    return result;
  }

  GameAlbum? album(String platform, String game) {
    for (final album in albums) {
      if (album.platform == platform && album.game == game) {
        return album;
      }
    }

    return null;
  }
}
