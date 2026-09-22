/// Where a published folder's tile image comes from.
///
/// The implementation that reads the covers shipped with the app lives in
/// `bundled_platform_covers.dart`, because that one needs Flutter and the
/// gallery itself does not.
abstract interface class PlatformCoverSource {
  /// The file name the cover is published under, or null when this platform
  /// has none. The extension follows the bundled image, so nothing is
  /// re-encoded on the way out.
  String? nameFor(String platform);

  /// The image itself, or null when this platform has none.
  Future<List<int>?> bytesFor(String platform);
}

/// Bundles nothing, for a gallery built without the app around it.
class NoPlatformCovers implements PlatformCoverSource {
  const NoPlatformCovers();

  @override
  String? nameFor(String platform) => null;

  @override
  Future<List<int>?> bytesFor(String platform) async => null;
}

/// The bundled file for each platform, by the folder name the library uses.
/// A platform that is not here simply has no cover yet; adding one is a file
/// in `assets/covers/platforms` and a line here.
const platformCoverAssets = {
  'Android': 'android.png',
  'Game Boy': 'game-boy.png',
  'Game Boy Advance': 'game-boy-advance.webp',
  'Game Boy Color': 'game-boy-color.png',
  'Nintendo Switch': 'nintendo-switch.png',
  'Nintendo Switch 2': 'nintendo-switch-2.webp',
  'PC': 'pc.png',
  'Pico-8': 'pico-8.webp',
  'PlayStation 4': 'playstation-4.png',
  'PlayStation 5': 'playstation-5.jpg',
  'Super Nintendo': 'super-nintendo.webp',
};

const platformCoverDirectory = 'assets/covers/platforms';

/// The asset key for [platform], or null when none is bundled. The folder name
/// is matched without regard to case or surrounding space, so a library
/// holding `playstation 5` still gets its cover.
String? platformCoverAsset(String platform) {
  final wanted = platform.trim().toLowerCase();
  for (final entry in platformCoverAssets.entries) {
    if (entry.key.toLowerCase() == wanted) {
      return '$platformCoverDirectory/${entry.value}';
    }
  }
  return null;
}
