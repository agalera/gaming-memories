/// A file the rendered pages link to that comes from the app rather than from
/// the library.
///
/// There is one so far — the logo in the footer — and it is published from the
/// build directory beside the pages, the same way a bundled platform cover is.
abstract interface class GalleryAssets {
  /// What the logo is published as, at the root of the site, or null when
  /// this build has none to give.
  String? get logoFileName;

  Future<List<int>?> logoBytes();
}

/// Ships nothing, for a gallery rendered without the app around it.
class NoGalleryAssets implements GalleryAssets {
  const NoGalleryAssets();

  @override
  String? get logoFileName => null;

  @override
  Future<List<int>?> logoBytes() async => null;
}

/// Where the logo lives in the app, and what it is called on the site.
const logoAsset = 'assets/logo.webp';
const publishedLogoName = 'gaming-memories.webp';
