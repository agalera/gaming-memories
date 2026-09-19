import 'dart:io';

class ScreenshotItem {
  const ScreenshotItem({
    required this.path,
    required this.platform,
    required this.game,
    required this.capturedAt,
    this.thumbnailPath,
  });

  final String path;
  final String platform;
  final String game;
  final DateTime capturedAt;
  final String? thumbnailPath;

  File get file => File(path);
  File get galleryFile => File(thumbnailPath ?? path);
}

class GameAlbum {
  const GameAlbum({
    required this.platform,
    required this.game,
    required this.screenshots,
  });

  final String platform;
  final String game;
  final List<ScreenshotItem> screenshots;
}

class ScreenshotLibrary {
  const ScreenshotLibrary({required this.albums});

  const ScreenshotLibrary.empty() : albums = const [];

  final List<GameAlbum> albums;

  List<ScreenshotItem> get timeline {
    final items = [for (final album in albums) ...album.screenshots];
    items.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return items;
  }

  List<ScreenshotItem> platformTimeline(String platform) {
    final items = [
      for (final album in albums)
        if (album.platform == platform) ...album.screenshots,
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
