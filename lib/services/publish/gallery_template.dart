import '../../models/app_settings.dart';
import 'gallery_node.dart';

/// Renders one album page: a grid of albums and captures, a filter, a sort,
/// and a lightbox.
///
/// The page carries its own stylesheet and script rather than linking to
/// either, so a published gallery is a folder of pages and captures with
/// nothing else beside it, and a page opened straight from disk works.
class GalleryTemplate {
  const GalleryTemplate({required this.site, this.logoPath});

  final PublishSiteSettings site;

  /// Where the logo sits on the site, or null when this build ships none and
  /// the footer goes without it.
  final String? logoPath;

  String render(GalleryPage page) {
    final folder = page.folder;
    final title = folder.isRoot ? _siteTitle : folder.name;
    final buffer = StringBuffer();

    buffer.writeln('<!doctype html>');
    buffer.writeln('<html lang="en">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8" />');
    buffer.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0" />',
    );
    buffer.writeln('<title>${_escape(_pageTitle(title))}</title>');
    buffer.writeln(
      '<meta name="theme-color" media="(prefers-color-scheme: light)" '
      'content="#ffffff" />',
    );
    buffer.writeln(
      '<meta name="theme-color" media="(prefers-color-scheme: dark)" '
      'content="#000000" />',
    );
    _writeOpenGraph(buffer, folder, title);
    buffer.writeln('<style type="text/css">');
    buffer.write(_styles);
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<div class="content">');
    _writeHeader(buffer, page);
    _writeFolders(buffer, folder);
    _writeFiles(buffer, folder);
    _writeFooter(buffer, folder);
    buffer.writeln('</div>');
    buffer.write(_lightboxMarkup);
    buffer.writeln('<script>');
    buffer.write(_script);
    buffer.writeln('</script>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  String get _siteTitle =>
      site.title.trim().isEmpty ? 'Gaming Memories' : site.title.trim();

  String _pageTitle(String title) {
    final suffix = site.title.trim();
    return suffix.isEmpty || title == suffix ? title : '$title | $suffix';
  }

  String get _heading {
    final author = site.author.trim();
    return author.isEmpty
        ? '$_siteTitle Gallery'
        : "$author's Videogames Screenshot Gallery";
  }

  /// The social card tags, which need an absolute URL to point at. A site
  /// without a configured base URL gets none rather than broken ones.
  void _writeOpenGraph(
    StringBuffer buffer,
    GalleryFolder folder,
    String title,
  ) {
    buffer.writeln('<meta property="og:title" content="${_escape(title)}" />');
    buffer.writeln('<meta property="og:type" content="website" />');

    final base = site.url.trim().replaceAll(RegExp(r'/+$'), '');
    if (folder.isRoot || base.isEmpty) {
      return;
    }

    buffer.writeln(
      '<meta property="og:url" content="${_escape('$base${folder.webPath}')}" />',
    );
    final cover = folder.coverWebPath;
    if (cover != null) {
      buffer.writeln(
        '<meta property="og:image" content="${_escape('$base$cover')}" />',
      );
    }
    final author = site.author.trim();
    if (author.isNotEmpty) {
      buffer.writeln(
        '<meta property="og:description" '
        'content="${_escape("$author's screenshots for $title")}" />',
      );
    }
  }

  void _writeHeader(StringBuffer buffer, GalleryPage page) {
    buffer.writeln('<header>');
    buffer.writeln('<h1>${_escape(_heading)}</h1>');

    if (!page.folder.isRoot) {
      buffer.writeln('<ul class="breadcrumbs">');
      for (final crumb in page.trail) {
        final label = crumb.isRoot ? _siteTitle : crumb.name;
        buffer.writeln(
          '<li><a href="${_escape(crumb.webPath)}">${_escape(label)}</a></li>',
        );
      }
      buffer.writeln('</ul>');
      buffer.writeln('<h2>${_escape(page.folder.name)}</h2>');
    }

    buffer.writeln('</header>');
  }

  void _writeFolders(StringBuffer buffer, GalleryFolder folder) {
    final children = folder.folders.where((child) => !child.isEmpty).toList();
    if (children.isEmpty) {
      return;
    }

    buffer.writeln('<ul class="gallery folders">');
    for (final child in children) {
      final cover = child.coverWebPath;
      final stats = _folderStats(child);
      buffer.writeln('<li>');
      buffer.writeln('<a href="${_escape(child.webPath)}">');
      if (cover != null) {
        buffer.writeln(
          '<img src="${_escape(cover)}" alt="" class="preview" '
          'loading="lazy" />',
        );
      }
      buffer.writeln('<span class="folder-caption">');
      buffer.writeln(
        '<span class="folder-title">${_escape(child.name)}</span>',
      );
      if (stats.isNotEmpty) {
        buffer.writeln('<span class="folder-stats">${_escape(stats)}</span>');
      }
      buffer.writeln('</span>');
      buffer.writeln('</a>');
      buffer.writeln('</li>');
    }
    buffer.writeln('</ul>');
  }

  static String _folderStats(GalleryFolder folder) {
    final images = folder.imageCount;
    final videos = folder.videoCount;
    final parts = [
      if (images > 0) '$images screenshot${images == 1 ? '' : 's'}',
      if (videos > 0) '$videos clip${videos == 1 ? '' : 's'}',
    ];
    return parts.isEmpty ? '' : '(${parts.join(' & ')})';
  }

  void _writeFiles(StringBuffer buffer, GalleryFolder folder) {
    if (folder.files.isEmpty) {
      return;
    }
    if (folder.folders.any((child) => !child.isEmpty)) {
      buffer.writeln('<hr />');
    }

    buffer.writeln('<div class="file-filters" id="fileFilters" hidden>');
    buffer.writeln(
      '<button class="filter-btn active" data-filter="all">All</button>',
    );
    buffer.writeln(
      '<button class="filter-btn" data-filter="image">Screenshots</button>',
    );
    buffer.writeln(
      '<button class="filter-btn" data-filter="video">Clips</button>',
    );
    buffer.writeln('<div class="sort-controls">');
    buffer.writeln('<span>Sort:</span>');
    buffer.writeln(
      '<button class="sort-btn" data-sort="asc">Oldest First</button>',
    );
    buffer.writeln(
      '<button class="sort-btn active" data-sort="desc">Newest First</button>',
    );
    buffer.writeln('</div>');
    buffer.writeln('</div>');

    buffer.writeln('<ul class="gallery files">');
    for (final file in folder.files) {
      final kind = file.isVideo ? 'video' : 'image';
      final preview = file.thumbnailPath == null
          ? folder.fileWebPath(file.name)
          : folder.fileWebPath(file.thumbnailName);
      buffer.writeln(
        '<li data-kind="$kind" data-filename="${_escape(file.name)}" '
        'data-date="${_escape(formatUpdated(file.capturedAt))}">',
      );
      buffer.writeln('<a href="${_escape(folder.fileWebPath(file.name))}">');
      buffer.writeln(
        '<img src="${_escape(preview)}" alt="${_escape(file.name)}" '
        'class="preview${file.isVideo ? ' video' : ''}" loading="lazy" />',
      );
      buffer.writeln('</a>');
      if (file.isVideo) {
        buffer.writeln('<div class="overlay-video">');
        buffer.writeln('<div class="play-icon"><span>&#9654;</span></div>');
        final duration = file.formattedDuration;
        if (duration.isNotEmpty) {
          buffer.writeln('<span class="duration">${_escape(duration)}</span>');
        }
        buffer.writeln('</div>');
      }
      buffer.writeln('</li>');
    }
    buffer.writeln('</ul>');
  }

  void _writeFooter(StringBuffer buffer, GalleryFolder folder) {
    buffer.writeln('<footer>');
    final footerText = site.footerText.trim();
    if (footerText.isNotEmpty) {
      buffer.writeln('<p>${_escape(footerText)}</p>');
    }
    // Kept as a machine-readable stamp too, so the date is not only a
    // sentence to a reader that wants to sort or index it.
    buffer.writeln(
      '<p>Last updated '
      '<time datetime="${_escape(folder.lastUpdated.toIso8601String())}">'
      '${_escape(formatUpdated(folder.lastUpdated))}</time></p>',
    );
    buffer.writeln(
      '<p class="made-with">Created using '
      '<a href="https://github.com/fmartingr/gaming-memories">'
      'Gaming Memories</a></p>',
    );
    final logo = logoPath;
    if (logo != null) {
      buffer.writeln(
        '<a class="footer-logo" '
        'href="https://github.com/fmartingr/gaming-memories">'
        '<img src="${_escape(logo)}" width="52" height="52" '
        'alt="Gaming Memories" loading="lazy" /></a>',
      );
    }
    buffer.writeln('</footer>');
  }

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// `6 September 2026 at 08:00`, in the time the capture carries rather than
  /// in UTC, so the date reads as the one the capture was taken on.
  static String formatUpdated(DateTime value) {
    final month = _monthNames[value.month - 1];
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.day} $month ${value.year} at $hour:$minute';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static const _styles = '''
:root {
  --bg: #ffffff;
  --surface: #ffffff;
  --surface-soft: #f5f5f5;
  --text: #000000;
  --muted: #5f5f5f;
  --subtle: #929292;
  --line: #dedede;
  --accent: #f36a35;
  --shadow: 0 1px 2px rgba(0, 0, 0, .04), 0 8px 24px rgba(0, 0, 0, .06);
  --shadow-hover: 0 2px 4px rgba(0, 0, 0, .06), 0 12px 32px rgba(0, 0, 0, .12);
  --radius: 14px;
  --radius-sm: 10px;
  --shell: 1120px;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #000000;
    --surface: #0d0d0d;
    --surface-soft: #171717;
    --text: #ffffff;
    --muted: #a3a3a3;
    --subtle: #7a7a7a;
    --line: #2d2d2d;
    --accent: #ff743d;
    --shadow: 0 1px 2px rgba(0, 0, 0, .5), 0 8px 24px rgba(0, 0, 0, .45);
    --shadow-hover: 0 2px 4px rgba(0, 0, 0, .6), 0 12px 32px rgba(0, 0, 0, .55);
  }
}

*, *::before, *::after { box-sizing: border-box; }

html { -webkit-text-size-adjust: 100%; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto,
    "Helvetica Neue", Arial, sans-serif;
  font-size: 15px;
  line-height: 1.5;
  -webkit-font-smoothing: antialiased;
}

a { color: inherit; text-decoration: none; }

.content {
  max-width: var(--shell);
  margin: 0 auto;
  padding: 40px 20px 72px;
}

header { margin-bottom: 28px; }

h1 {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--muted);
}

h2 {
  margin: 10px 0 0;
  font-size: 30px;
  font-weight: 700;
  letter-spacing: -0.03em;
}

.breadcrumbs {
  list-style: none;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  margin: 18px 0 0;
  padding: 0;
  font-size: 13px;
  color: var(--muted);
}

.breadcrumbs li { display: flex; align-items: center; gap: 6px; }
.breadcrumbs li::after { content: "/"; color: var(--line); }
.breadcrumbs li:last-child::after { content: ""; }
.breadcrumbs a {
  padding: 3px 8px;
  border-radius: 999px;
  transition: background-color .15s ease, color .15s ease;
}
.breadcrumbs a:hover { background: var(--surface-soft); color: var(--text); }
.breadcrumbs li:last-child a { color: var(--text); font-weight: 600; }

hr {
  height: 1px;
  margin: 32px 0;
  border: 0;
  background: var(--line);
}

/* Every tile is as tall as its own image. Nothing here says what shape that
   is: an image with a width and no height keeps its own ratio, so a wide
   store banner, a square console cover, a 16:9 capture and a Game Boy's
   10:9 one each get the tile they need without anything having to measure
   them. A row is as tall as the tallest tile in it, and the shorter ones sit
   at its top. */
.gallery {
  list-style: none;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
  align-items: start;
  gap: 18px;
  margin: 0;
  padding: 0;
}

.gallery li { position: relative; min-width: 0; }
.gallery li[hidden] { display: none; }

.gallery .preview {
  display: block;
  width: 100%;
  height: auto;
  border-radius: var(--radius);
  background: var(--surface-soft);
  border: 1px solid var(--line);
  transition: transform .18s ease, box-shadow .18s ease,
    border-color .18s ease;
}

/* An album tile is one image with its name over it, the way a capture tile
   is one image. */
.gallery.folders li a {
  position: relative;
  display: block;
  border-radius: var(--radius);
  overflow: hidden;
}

.gallery.folders .preview {
  border-radius: 0;
  border: 0;
}

.gallery.folders li a::after {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: var(--radius);
  border: 1px solid var(--line);
  pointer-events: none;
}

.folder-caption {
  position: absolute;
  inset: auto 0 0 0;
  padding: 34px 12px 11px;
  /* The name sits over whatever the cover happens to be — a dark screenshot,
     box art, or a logo on white — so the fade has to carry it on its own. */
  background: linear-gradient(
    to top,
    rgba(0, 0, 0, .92) 0%,
    rgba(0, 0, 0, .78) 30%,
    rgba(0, 0, 0, .38) 65%,
    rgba(0, 0, 0, 0) 100%
  );
  color: #ffffff;
}

.gallery li a:hover .preview {
  transform: translateY(-2px);
  box-shadow: var(--shadow-hover);
  border-color: var(--subtle);
}

/* The tile itself lifts, or the image would slide out from under its name. */
.gallery.folders li a:hover .preview { transform: none; }

.gallery.folders li a {
  transition: transform .18s ease, box-shadow .18s ease;
}

.gallery.folders li a:hover {
  transform: translateY(-2px);
  box-shadow: var(--shadow-hover);
}

.gallery li a:focus-visible .preview {
  outline: 2px solid var(--accent);
  outline-offset: 3px;
}

.folder-title {
  display: block;
  font-size: 14px;
  font-weight: 600;
  letter-spacing: -0.01em;
  text-shadow: 0 1px 3px rgba(0, 0, 0, .5);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.folder-stats {
  display: block;
  margin-top: 1px;
  font-size: 12px;
  color: rgba(255, 255, 255, .78);
  text-shadow: 0 1px 3px rgba(0, 0, 0, .5);
}

.overlay-video {
  position: absolute;
  top: 8px;
  right: 8px;
  display: flex;
  align-items: center;
  gap: 5px;
  height: 22px;
  padding: 0 8px;
  border-radius: 999px;
  background: rgba(0, 0, 0, .72);
  color: #ffffff;
  backdrop-filter: blur(6px);
}

.overlay-video .play-icon {
  display: flex;
  align-items: center;
  font-size: 9px;
  line-height: 1;
}

.overlay-video .duration {
  font-size: 11px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}

/* A class beats the browser's own [hidden] rule, so it has to be said here
   or the filters show on an album that has nothing to filter. */
.file-filters[hidden] { display: none; }

.file-filters {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin: 0 0 22px;
}

.sort-controls {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-left: auto;
  font-size: 13px;
  color: var(--subtle);
}

.filter-btn, .sort-btn {
  appearance: none;
  padding: 7px 14px;
  border: 1px solid var(--line);
  border-radius: 999px;
  background: var(--surface);
  color: var(--muted);
  font: inherit;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition: background-color .15s ease, color .15s ease,
    border-color .15s ease;
}

.filter-btn:hover, .sort-btn:hover {
  background: var(--surface-soft);
  color: var(--text);
}

.filter-btn.active, .sort-btn.active {
  background: var(--text);
  border-color: var(--text);
  color: var(--bg);
}

footer {
  margin-top: 56px;
  padding-top: 24px;
  border-top: 1px solid var(--line);
  text-align: center;
  font-size: 12px;
  color: var(--subtle);
}

footer p { margin: 5px 0; }

.made-with a {
  font-weight: 600;
  color: var(--muted);
  transition: color .15s ease;
}

.made-with a:hover { color: var(--accent); }

.footer-logo {
  display: inline-block;
  margin-top: 14px;
  line-height: 0;
  opacity: .85;
  transition: opacity .15s ease, transform .15s ease;
}

.footer-logo:hover { opacity: 1; transform: translateY(-1px); }

.footer-logo img { display: block; width: 52px; height: 52px; }

.lightbox {
  display: none;
  position: fixed;
  inset: 0;
  z-index: 999;
  padding: 24px;
  background: rgba(0, 0, 0, .92);
  backdrop-filter: blur(8px);
}

.lightbox.active {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 14px;
}

.lightbox-caption {
  margin: 0;
  min-height: 18px;
  font-size: 13px;
  font-variant-numeric: tabular-nums;
  color: rgba(255, 255, 255, .72);
  text-align: center;
}

.lightbox img, .lightbox video {
  max-width: 92vw;
  max-height: 82vh;
  border-radius: var(--radius);
  object-fit: contain;
}

.lightbox .close, .lightbox .nav {
  position: absolute;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 999px;
  background: rgba(255, 255, 255, .1);
  color: #ffffff;
  cursor: pointer;
  user-select: none;
  z-index: 1000;
  transition: background-color .15s ease;
}

.lightbox .close:hover, .lightbox .nav:hover {
  background: rgba(255, 255, 255, .2);
}

.lightbox .close {
  top: 20px;
  right: 20px;
  width: 40px;
  height: 40px;
  font-size: 24px;
  line-height: 1;
}

.lightbox .nav {
  top: 50%;
  width: 44px;
  height: 44px;
  font-size: 20px;
  transform: translateY(-50%);
}

.lightbox .prev { left: 20px; }
.lightbox .next { right: 20px; }

@media (max-width: 640px) {
  .content { padding: 28px 16px 56px; }
  h2 { font-size: 24px; }
  .gallery { grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 12px; }
  .sort-controls { margin-left: 0; width: 100%; }
  .lightbox .nav { width: 38px; height: 38px; }
}

@media (prefers-reduced-motion: reduce) {
  * { transition: none !important; }
}
''';

  /// Settles the theme before the first paint, so a page opened with the
  /// dark theme chosen does not flash white on its way there.
  static const _lightboxMarkup = '''
<div class="lightbox">
  <div class="close">&times;</div>
  <div class="nav prev">&lt;</div>
  <div class="nav next">&gt;</div>
  <div class="content-wrapper"></div>
  <p class="lightbox-caption"></p>
</div>
''';

  static const _script = r'''
document.addEventListener('DOMContentLoaded', () => {
  const lightbox = document.querySelector('.lightbox');
  const contentWrapper = lightbox.querySelector('.content-wrapper');
  const caption = lightbox.querySelector('.lightbox-caption');
  // The files list, not the folder list above it: a page showing both has two
  // `.gallery` lists, and only the captures open in the lightbox.
  const gallery = document.querySelector('.gallery.files');
  let currentIndex = 0;
  let items = [];
  let touchStartX = 0;
  let touchEndX = 0;

  function updateItems() {
    items = Array.from(
      document.querySelectorAll('.gallery.files li:not([hidden]) a'),
    );
  }

  function showLightbox(index) {
    if (index < 0 || index >= items.length) return;

    currentIndex = index;
    const item = items[currentIndex];
    if (!item || typeof item.href !== 'string') return;

    const path = item.href;
    const isVideo = item.querySelector('.video') !== null;

    contentWrapper.innerHTML = '';
    const media = document.createElement(isVideo ? 'video' : 'img');
    media.src = path;
    if (isVideo) {
      media.controls = true;
      media.autoplay = true;
    } else {
      media.alt = '';
    }
    contentWrapper.appendChild(media);

    // The date rides on the tile, so opening one needs no second lookup.
    const tile = item.closest('li');
    caption.textContent = tile ? tile.dataset.date || '' : '';

    lightbox.classList.add('active');
    history.replaceState(null, null, '#' + path.split('/').pop());
  }

  function closeLightbox() {
    lightbox.classList.remove('active');
    caption.textContent = '';
    const video = contentWrapper.querySelector('video');
    if (video) {
      video.pause();
      video.currentTime = 0;
    }
    history.replaceState(null, null, ' ');
  }

  function findIndexByFilename(filename) {
    return items.findIndex(item => item.href.split('/').pop() === filename);
  }

  function handleHashChange() {
    const hash = window.location.hash.slice(1);
    if (hash) {
      const index = findIndexByFilename(hash);
      if (index !== -1) showLightbox(index);
    } else {
      closeLightbox();
    }
  }

  lightbox.querySelector('.close').addEventListener('click', closeLightbox);

  lightbox.addEventListener('click', (e) => {
    if (e.target === lightbox) closeLightbox();
  });

  const filterButtons = document.querySelectorAll('.filter-btn');
  const fileFilters = document.getElementById('fileFilters');
  const fileItems = document.querySelectorAll('.gallery.files li');

  let hasImages = false;
  let hasVideos = false;
  fileItems.forEach(item => {
    const kind = item.getAttribute('data-kind');
    if (kind === 'image') hasImages = true;
    if (kind === 'video') hasVideos = true;
  });
  if (hasImages && hasVideos && fileFilters) {
    fileFilters.hidden = false;
  }

  filterButtons.forEach(button => {
    button.addEventListener('click', () => {
      const filter = button.getAttribute('data-filter');
      filterButtons.forEach(btn => btn.classList.remove('active'));
      button.classList.add('active');
      fileItems.forEach(item => {
        const kind = item.getAttribute('data-kind');
        item.hidden = !(filter === 'all' || filter === kind);
      });
      updateItems();
      if (lightbox.classList.contains('active')) closeLightbox();
    });
  });

  const prev = lightbox.querySelector('.prev');
  const next = lightbox.querySelector('.next');

  prev.addEventListener('click', () => {
    if (items.length > 0) showLightbox((currentIndex - 1 + items.length) % items.length);
  });

  next.addEventListener('click', () => {
    if (items.length > 0) showLightbox((currentIndex + 1) % items.length);
  });

  document.addEventListener('keydown', (e) => {
    if (!lightbox.classList.contains('active')) return;
    if (e.key === 'Escape') closeLightbox();
    if (e.key === 'ArrowLeft') prev.click();
    if (e.key === 'ArrowRight') next.click();
  });

  contentWrapper.addEventListener('touchstart', (e) => {
    touchStartX = e.changedTouches[0].screenX;
  }, false);

  contentWrapper.addEventListener('touchend', (e) => {
    touchEndX = e.changedTouches[0].screenX;
    const diff = touchStartX - touchEndX;
    if (items.length > 0 && Math.abs(diff) > 50) {
      showLightbox((currentIndex + (diff > 0 ? 1 : -1) + items.length) % items.length);
    }
  }, false);

  contentWrapper.addEventListener('touchmove', (e) => {
    e.preventDefault();
  }, { passive: false });

  const sortButtons = document.querySelectorAll('.sort-btn');
  let currentSort = 'desc';

  function sortItems() {
    const galleryFiles = document.querySelector('.gallery.files');
    if (!galleryFiles) return;
    const sorted = Array.from(galleryFiles.querySelectorAll('li'));
    sorted.sort((a, b) => {
      const nameA = a.getAttribute('data-filename');
      const nameB = b.getAttribute('data-filename');
      return currentSort === 'asc' ? nameA.localeCompare(nameB) : nameB.localeCompare(nameA);
    });
    sorted.forEach(item => galleryFiles.appendChild(item));
    updateItems();
  }

  sortButtons.forEach(button => {
    button.addEventListener('click', () => {
      sortButtons.forEach(btn => btn.classList.remove('active'));
      button.classList.add('active');
      currentSort = button.getAttribute('data-sort');
      sortItems();
      if (lightbox.classList.contains('active')) closeLightbox();
    });
  });

  sortItems();
  updateItems();

  if (gallery) {
    gallery.addEventListener('click', (e) => {
      const clickedAnchor = e.target.closest('a');
      if (!clickedAnchor) return;
      const fileItem = clickedAnchor.closest('.gallery.files li');
      if (!fileItem) return;
      if (!fileItem.hidden) {
        e.preventDefault();
        const index = items.findIndex(item => item === clickedAnchor);
        if (index !== -1) showLightbox(index);
      }
    });
  }

  window.addEventListener('hashchange', handleHashChange);
  handleHashChange();
});
''';
}
