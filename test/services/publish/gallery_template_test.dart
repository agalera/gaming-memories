import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/publish/gallery_node.dart';
import 'package:gaming_memories/services/publish/gallery_template.dart';

GalleryFile file(
  String name, {
  GalleryFileKind kind = GalleryFileKind.image,
  bool thumbnail = true,
  Duration? duration,
  DateTime? capturedAt,
}) {
  return GalleryFile(
    name: name,
    sourcePath: '/library/$name',
    kind: kind,
    modified: DateTime.utc(2026, 3, 1),
    capturedAt: capturedAt ?? DateTime(2026, 3, 1, 12),
    size: 10,
    thumbnailPath: thumbnail ? '/library/$name.thumb.jpg' : null,
    duration: duration,
  );
}

GalleryFolder folder({
  String name = 'Hades',
  String relativePath = 'Steam/Hades',
  List<GalleryFolder> folders = const [],
  List<GalleryFile> files = const [],
  String? coverName,
}) {
  return GalleryFolder(
    name: name,
    relativePath: relativePath,
    folders: folders,
    files: files,
    lastUpdated: DateTime.utc(2026, 3, 1, 12),
    cover: coverName == null
        ? null
        : GalleryCover.fromLibrary(
            name: coverName,
            source: '/library/$coverName',
          ),
  );
}

const site = PublishSiteSettings(
  title: 'Games Screenshots',
  author: '@fmartingr',
  url: 'https://screenshots.example.com',
  footerText: 'Be wary of spoilers!',
);

void main() {
  test('escapes a title holding markup characters', () {
    final album = folder(
      name: 'Tom & Jerry <"Quoted">',
      relativePath: 'PC/Tom & Jerry',
      files: [file('a.png')],
    );
    final page = album.pages().first;

    final html = const GalleryTemplate(site: site).render(page);

    expect(html, contains('Tom &amp; Jerry &lt;&quot;Quoted&quot;&gt;'));
    expect(html, isNot(contains('<"Quoted">')));
  });

  test('percent-encodes every path segment of a link', () {
    final album = folder(
      name: 'Run 1',
      relativePath: 'Steam/Hades/Run 1',
      files: [file('shot #1.png')],
    );

    final html = const GalleryTemplate(site: site).render(album.pages().first);

    expect(html, contains('href="/Steam/Hades/Run%201/shot%20%231.png"'));
    expect(
      html,
      contains('src="/Steam/Hades/Run%201/shot%20%231.png.thumb.jpg"'),
    );
  });

  test('a clip shows the play icon, and its length when one is known', () {
    final withDuration = folder(
      files: [
        file(
          'clip.mp4',
          kind: GalleryFileKind.video,
          duration: const Duration(seconds: 95),
        ),
      ],
    );
    final withoutDuration = folder(
      files: [file('clip.mp4', kind: GalleryFileKind.video)],
    );

    final template = const GalleryTemplate(site: site);
    final shown = template.render(withDuration.pages().first);
    final bare = template.render(withoutDuration.pages().first);

    expect(shown, contains('class="overlay-video"'));
    expect(shown, contains('<span class="duration">1:35</span>'));
    expect(bare, contains('class="overlay-video"'));
    expect(bare, isNot(contains('class="duration"')));
  });

  test('a child page carries the social card, the root does not', () {
    final child = folder(coverName: 'cover.jpg', files: [file('a.png')]);
    final root = GalleryFolder(
      name: 'Games Screenshots',
      relativePath: '',
      folders: [child],
      files: const [],
      lastUpdated: DateTime.utc(2026, 3, 1),
    );

    final template = const GalleryTemplate(site: site);
    final childHtml = template.render(child.pages().first);
    final rootHtml = template.render(root.pages().first);

    expect(
      childHtml,
      contains('content="https://screenshots.example.com/Steam/Hades/"'),
    );
    expect(
      childHtml,
      contains(
        'content="https://screenshots.example.com/Steam/Hades/cover.jpg"',
      ),
    );
    expect(childHtml, contains("@fmartingr&#39;s screenshots for Hades"));
    expect(rootHtml, isNot(contains('og:url')));
  });

  test('a site without an address gets no social card links', () {
    const bare = PublishSiteSettings(
      title: 'Games',
      author: '',
      url: '',
      footerText: '',
    );
    final album = folder(files: [file('a.png')]);

    final html = const GalleryTemplate(site: bare).render(album.pages().first);

    expect(html, contains('og:title'));
    expect(html, isNot(contains('og:url')));
    expect(html, isNot(contains('og:image')));
  });

  test('tile counts name screenshots and clips, and pluralise', () {
    final one = folder(
      name: 'One',
      relativePath: 'Steam/One',
      files: [file('a.png')],
    );
    final many = folder(
      name: 'Many',
      relativePath: 'Steam/Many',
      files: [
        file('a.png'),
        file('b.png'),
        file('c.mp4', kind: GalleryFileKind.video),
      ],
    );
    final platform = folder(
      name: 'Steam',
      relativePath: 'Steam',
      folders: [one, many],
    );

    final html = const GalleryTemplate(site: site)
        .render(platform.pages().first);

    expect(html, contains('(1 screenshot)'));
    expect(html, contains('(2 screenshots &amp; 1 clip)'));
  });

  test('an album tile is one image with its name over it', () {
    final album = folder(
      name: 'Hades',
      relativePath: 'Steam/Hades',
      coverName: 'cover.jpg',
      files: [file('a.png')],
    );
    final platform = folder(
      name: 'Steam',
      relativePath: 'Steam',
      folders: [album],
    );

    final html = const GalleryTemplate(site: site)
        .render(platform.pages().first);

    expect(html, contains('class="folder-caption"'));

    // The tile takes its image's own shape, for a cover and a capture alike.
    // Sources hand over whatever ratio they like — a Steam banner is 2.14, a
    // console cover is square, a Game Boy capture is 10:9 — and none of them
    // is cropped to a shape the page picked.
    final rule = html.substring(html.indexOf('.gallery .preview {'));
    final declarations = rule.substring(0, rule.indexOf('}'));
    expect(declarations, contains('height: auto'));
    expect(declarations, isNot(contains('aspect-ratio')));
    expect(declarations, isNot(contains('object-fit')));
    // A row is as tall as its tallest tile, and the shorter ones sit at the
    // top of it rather than being stretched down.
    expect(html, contains('align-items: start;'));
    expect(
      html.indexOf('class="folder-caption"'),
      greaterThan(html.indexOf('src="/Steam/Hades/cover.jpg"')),
    );
  });

  test('a capture with no thumbnail falls back to itself', () {
    final album = folder(files: [file('a.png', thumbnail: false)]);

    final html = const GalleryTemplate(site: site).render(album.pages().first);

    expect(html, contains('src="/Steam/Hades/a.png"'));
    expect(html, isNot(contains('a.png.thumb.jpg')));
  });

  test('draws the breadcrumb trail on a child page', () {
    final album = folder(files: [file('a.png')]);
    final page = GalleryPage(
      folder: album,
      trail: [
        folder(name: 'Games Screenshots', relativePath: ''),
        folder(name: 'Steam', relativePath: 'Steam'),
        album,
      ],
    );

    final html = const GalleryTemplate(site: site).render(page);

    expect(html, contains('<a href="/">Games Screenshots</a>'));
    expect(html, contains('<a href="/Steam/">Steam</a>'));
    expect(html, contains('<a href="/Steam/Hades/">Hades</a>'));
  });

  test('the footer carries the configured text and the last update', () {
    final album = folder(files: [file('a.png')]);

    final html = const GalleryTemplate(site: site).render(album.pages().first);

    expect(html, contains('Be wary of spoilers!'));
    // A date a reader can read, with the machine-readable stamp kept beside
    // it for anything that wants to sort or index the page.
    expect(html, contains('Last updated'));
    expect(html, contains('>1 March 2026 at 12:00<'));
    expect(html, contains('<time datetime="2026-03-01T12:00:00.000Z"'));
  });

  test('a readable date covers the awkward parts of a year', () {
    expect(
      GalleryTemplate.formatUpdated(DateTime(2026, 1, 1, 0, 0)),
      '1 January 2026 at 00:00',
    );
    expect(
      GalleryTemplate.formatUpdated(DateTime(2026, 12, 31, 23, 9)),
      '31 December 2026 at 23:09',
    );
    expect(
      GalleryTemplate.formatUpdated(DateTime(2026, 9, 6, 8, 5)),
      '6 September 2026 at 08:05',
    );
  });
  test('the logo sits below the credit line', () {
    final album = folder(files: [file('a.png')]);

    final html = const GalleryTemplate(
      site: site,
      logoPath: '/gaming-memories.webp',
    ).render(album.pages().first);

    expect(html, contains('class="made-with"'));
    expect(
      html,
      contains('href="https://github.com/fmartingr/gaming-memories"'),
    );
    expect(html, contains('class="footer-logo"'));
    expect(html, contains('src="/gaming-memories.webp"'));
    expect(
      html.indexOf('class="footer-logo"'),
      greaterThan(html.indexOf('class="made-with"')),
    );
  });

  test('a build with no logo leaves the footer without one', () {
    final album = folder(files: [file('a.png')]);

    final html = const GalleryTemplate(site: site).render(album.pages().first);

    expect(html, contains('Created using'));
    // The rule for it is always in the stylesheet; what matters is that
    // nothing links to a file this build does not publish.
    expect(html, isNot(contains('class="footer-logo"')));
    expect(html, isNot(contains('gaming-memories.webp')));
  });

  test('the theme follows the reader, with nothing to press', () {
    final album = folder(files: [file('a.png')]);

    final html = const GalleryTemplate(site: site).render(album.pages().first);

    expect(html, contains('@media (prefers-color-scheme: dark)'));
    // Declared rather than scripted, so there is no control and no stored
    // choice to keep in step with one.
    expect(html, isNot(contains('data-theme')));
    expect(html, isNot(contains('gaming-memories-theme')));
    expect(html, isNot(contains('theme-toggle')));
    expect(
      html,
      contains(
        '<meta name="theme-color" media="(prefers-color-scheme: dark)" '
        'content="#000000" />',
      ),
    );
  });

  test('the page carries its own styles and script', () {
    final album = folder(files: [file('a.png')]);

    final html = const GalleryTemplate(site: site).render(album.pages().first);

    // A page opened straight from disk has to work.
    expect(html, isNot(contains('<link rel="stylesheet"')));
    expect(html, isNot(contains('<script src=')));
    expect(html, contains('grid-template-columns'));
  });

  test('the filters start hidden and the grid respects it', () {
    final album = folder(
      files: [
        file('a.png'),
        file('c.mp4', kind: GalleryFileKind.video),
      ],
    );

    final html = const GalleryTemplate(site: site).render(album.pages().first);

    // Filtering toggles the attribute rather than an inline display the
    // layout would then have to agree with.
    expect(html, contains('id="fileFilters" hidden'));
    expect(html, contains('.gallery li[hidden] { display: none; }'));
    // A class beats the browser's own [hidden] rule, so both need saying.
    expect(html, contains('.file-filters[hidden] { display: none; }'));
    expect(html, contains('item.hidden = !('));
  });
  test('a capture carries its date for the lightbox to show', () {
    final album = folder(
      files: [
        file('a.png', capturedAt: DateTime(2024, 12, 31, 8, 23, 12)),
        file(
          'c.mp4',
          kind: GalleryFileKind.video,
          capturedAt: DateTime(2025, 1, 1, 0, 5),
        ),
      ],
    );

    final html = const GalleryTemplate(site: site).render(album.pages().first);

    // It rides on the tile, so opening one needs no second lookup.
    expect(html, contains('data-date="31 December 2024 at 08:23"'));
    expect(html, contains('data-date="1 January 2025 at 00:05"'));
    expect(html, contains('class="lightbox-caption"'));
    expect(html, contains('caption.textContent = tile ? tile.dataset.date'));
  });

  test('the lightbox fetches the neighbouring images, never a clip', () {
    final album = folder(files: [file('a.png'), file('b.png')]);

    final html = const GalleryTemplate(site: site).render(album.pages().first);

    // Every open, arrow and swipe goes through showLightbox, so the preload
    // runs on each of them.
    final show = html.substring(html.indexOf('function showLightbox('));
    expect(
      show.substring(0, show.indexOf('function preloadNeighbours()')),
      contains('preloadNeighbours();'),
    );
    final preload = html.substring(
      html.indexOf('function preloadNeighbours()'),
    );
    final body = preload.substring(0, preload.indexOf('\n  }\n'));
    expect(body, contains('[currentIndex + 1, currentIndex - 1]'));
    expect(body, contains("item.querySelector('.video') !== null) return;"));
    expect(body, contains('new Image()'));
    expect(body, contains('preloaded = kept;'));
  });

  test('the caption is cleared when the lightbox closes', () {
    final album = folder(files: [file('a.png')]);

    final html = const GalleryTemplate(site: site).render(album.pages().first);

    // Otherwise the last date lingers behind the next image while it loads.
    final close = html.substring(html.indexOf('function closeLightbox()'));
    expect(
      close.substring(0, close.indexOf('}')),
      contains("caption.textContent = ''"),
    );
  });
}
