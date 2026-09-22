import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gallery_assets.dart';
import 'platform_covers.dart';

/// The covers shipped with the app, one per platform the library can hold.
///
/// A game album gets its cover from a `cover.*` file a source wrote beside it,
/// but nothing writes one into a platform folder. Without this, a platform
/// tile on the site's front page falls back to whichever capture happens to
/// come first below it.
class BundledPlatformCovers implements PlatformCoverSource {
  const BundledPlatformCovers({this.bundle});

  /// Left null in the app so the usual asset bundle is used. Tests hand in
  /// their own rather than depending on a Flutter binding.
  final AssetBundle? bundle;

  @override
  String? nameFor(String platform) {
    final asset = platformCoverAsset(platform);
    if (asset == null) {
      return null;
    }
    return 'cover${_extensionOf(asset)}';
  }

  @override
  Future<List<int>?> bytesFor(String platform) async {
    final asset = platformCoverAsset(platform);
    if (asset == null) {
      return null;
    }
    try {
      final data = await (bundle ?? rootBundle).load(asset);
      return Uint8List.sublistView(data);
    } on FlutterError {
      // A cover that cannot be read is not worth failing a publish over; the
      // tile falls back to a capture from below the platform.
      return null;
    }
  }

  static String _extensionOf(String asset) {
    final dot = asset.lastIndexOf('.');
    return dot == -1 ? '' : asset.substring(dot);
  }
}

/// The logo shipped with the app, published beside the pages so the footer
/// shows the real mark rather than something drawn to look like it.
class BundledGalleryAssets implements GalleryAssets {
  const BundledGalleryAssets({this.bundle});

  final AssetBundle? bundle;

  @override
  String? get logoFileName => publishedLogoName;

  @override
  Future<List<int>?> logoBytes() async {
    try {
      final data = await (bundle ?? rootBundle).load(logoAsset);
      return Uint8List.sublistView(data);
    } on FlutterError {
      // A footer without the mark still reads; a publish that failed over it
      // would not.
      return null;
    }
  }
}
