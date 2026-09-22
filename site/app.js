const repository = 'fmartingr/gaming-memories';
const releasesUrl = `https://github.com/${repository}/releases`;
const latestReleaseUrl = `${releasesUrl}/latest`;

document.documentElement.classList.add('js');

function platformKey() {
  const value = `${navigator.userAgentData?.platform || ''} ${navigator.platform || ''} ${navigator.userAgent || ''}`.toLowerCase();
  if (value.includes('win')) return 'windows';
  if (value.includes('mac')) return 'macos';
  if (value.includes('linux')) return 'linux';
  return 'other';
}

const platformDetails = {
  windows: { name: 'Windows', match: (name) => name.endsWith('-windows-x64.exe') },
  macos: { name: 'macOS', match: (name) => name.endsWith('-macos-universal.dmg') },
  linux: { name: 'Linux', match: (name) => name.endsWith('_amd64.deb') },
};

function setFallbackReleaseState() {
  document.querySelectorAll('[data-smart-download]').forEach((link) => {
    link.href = releasesUrl;
  });
  document.querySelectorAll('[data-release-status]').forEach((item) => {
    item.textContent = 'The first public build is not available yet. Open the release page for current status.';
  });
  document.querySelectorAll('[data-download-label]').forEach((item) => {
    item.textContent = 'View releases';
  });
}

function applyRelease(release) {
  const assets = release.assets || [];
  const currentPlatform = platformKey();
  const current = platformDetails[currentPlatform];
  const releasePage = release.html_url || latestReleaseUrl;
  const selectedAsset = current ? assets.find((asset) => current.match(asset.name)) : null;

  document.querySelectorAll('[data-release-version]').forEach((item) => {
    item.textContent = release.tag_name || 'Latest release';
  });

  document.querySelectorAll('[data-smart-download]').forEach((link) => {
    link.href = selectedAsset?.browser_download_url || releasePage;
  });

  document.querySelectorAll('[data-download-label]').forEach((item) => {
    item.textContent = selectedAsset ? `Download for ${current.name}` : 'Download latest';
  });

  Object.entries(platformDetails).forEach(([key, details]) => {
    const link = document.querySelector(`[data-platform-download="${key}"]`);
    if (!link) return;
    const asset = assets.find((candidate) => details.match(candidate.name));
    link.href = asset?.browser_download_url || releasePage;
  });
}

async function loadLatestRelease() {
  try {
    const response = await fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json' },
    });
    if (response.status === 404) {
      setFallbackReleaseState();
      return;
    }
    if (!response.ok) return;
    applyRelease(await response.json());
  } catch (_) {
    // The static release links remain useful when the API is unavailable.
  }
}

function setUpNavigation() {
  const button = document.querySelector('.nav-toggle');
  const links = document.querySelector('.nav-links');
  if (!button || !links) return;
  button.addEventListener('click', () => {
    const open = button.getAttribute('aria-expanded') === 'true';
    button.setAttribute('aria-expanded', String(!open));
    links.classList.toggle('open', !open);
  });
  links.addEventListener('click', (event) => {
    if (event.target.closest('a')) {
      button.setAttribute('aria-expanded', 'false');
      links.classList.remove('open');
    }
  });
}

function activeTheme() {
  const selected = document.documentElement.dataset.theme;
  if (selected === 'light' || selected === 'dark') return selected;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function updateThemeControls() {
  const theme = activeTheme();
  const nextTheme = theme === 'dark' ? 'light' : 'dark';
  document.querySelector('meta[name="theme-color"]')?.setAttribute(
    'content',
    theme === 'dark' ? '#000000' : '#ffffff',
  );
  document.querySelectorAll('[data-theme-toggle]').forEach((button) => {
    const label = `Use ${nextTheme} theme`;
    button.setAttribute('aria-label', label);
    button.setAttribute('title', label);
  });
}

function setUpTheme() {
  const systemTheme = window.matchMedia('(prefers-color-scheme: dark)');
  document.querySelectorAll('[data-theme-toggle]').forEach((button) => {
    button.addEventListener('click', () => {
      const theme = activeTheme() === 'dark' ? 'light' : 'dark';
      document.documentElement.dataset.theme = theme;
      try {
        localStorage.setItem('gaming-memories-theme', theme);
      } catch (_) {
        // The selected theme remains active for this page.
      }
      updateThemeControls();
    });
  });
  systemTheme.addEventListener?.('change', () => {
    if (!document.documentElement.dataset.theme) updateThemeControls();
  });
  updateThemeControls();
}

function setUpReveal() {
  const items = document.querySelectorAll('[data-reveal]');
  if (!items.length) return;
  if (!('IntersectionObserver' in window) || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    items.forEach((item) => item.classList.add('revealed'));
    return;
  }
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('revealed');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12 });
  items.forEach((item) => observer.observe(item));
}

function setUpTabs() {
  const tabs = document.querySelectorAll('[data-doc-tab]');
  tabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      const key = tab.dataset.docTab;
      tabs.forEach((item) => {
        const active = item === tab;
        item.classList.toggle('active', active);
        item.setAttribute('aria-selected', String(active));
      });
      document.querySelectorAll('[data-doc-panel]').forEach((panel) => {
        const active = panel.dataset.docPanel === key;
        panel.classList.toggle('active', active);
        panel.hidden = !active;
      });
    });
  });
}

async function copyText(button, text) {
  try {
    await navigator.clipboard.writeText(text);
    const original = button.textContent;
    button.textContent = 'Copied';
    window.setTimeout(() => { button.textContent = original; }, 1600);
  } catch (_) {
    button.textContent = 'Select text';
  }
}

function setUpCopyButtons() {
  document.querySelectorAll('.copy-button').forEach((button) => {
    button.addEventListener('click', () => {
      const container = button.closest('.code-block, .command-list > div');
      const code = container?.querySelector('code');
      if (code) copyText(button, code.textContent.trim());
    });
  });
}

function setUpDetails() {
  document.querySelectorAll('details').forEach((detail) => {
    detail.addEventListener('toggle', () => {
      const icon = detail.querySelector('summary span');
      if (icon) icon.textContent = detail.open ? '−' : '+';
    });
    if (detail.open) {
      const icon = detail.querySelector('summary span');
      if (icon) icon.textContent = '−';
    }
  });
}

function setUpScreenshotCarousel() {
  const carousel = document.querySelector('[data-screenshot-carousel]');
  const slides = [...document.querySelectorAll('[data-screenshot-slide]')];
  if (!carousel || slides.length < 2) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let currentSlide = 0;
  let timer;

  function showSlide(index) {
    currentSlide = index;
    slides.forEach((slide, slideIndex) => {
      const active = slideIndex === currentSlide;
      slide.classList.toggle('is-active', active);
      slide.setAttribute('aria-hidden', String(!active));
    });
  }

  function stop() {
    window.clearInterval(timer);
    timer = undefined;
  }

  function start() {
    stop();
    if (reducedMotion.matches || document.hidden) return;
    timer = window.setInterval(() => {
      showSlide((currentSlide + 1) % slides.length);
    }, 10000);
  }

  document.addEventListener('visibilitychange', start);
  reducedMotion.addEventListener?.('change', start);
  showSlide(0);
  start();
}

setUpNavigation();
setUpTheme();
setUpReveal();
setUpTabs();
setUpCopyButtons();
setUpDetails();
setUpScreenshotCarousel();
loadLatestRelease();
