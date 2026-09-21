let selectedTheme;
try {
  selectedTheme = localStorage.getItem('gaming-memories-theme');
  if (selectedTheme === 'light' || selectedTheme === 'dark') {
    document.documentElement.dataset.theme = selectedTheme;
  }
} catch (_) {
  // The system theme remains active when storage is unavailable.
}

const initialTheme = selectedTheme === 'light' || selectedTheme === 'dark'
  ? selectedTheme
  : window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
document.querySelector('meta[name="theme-color"]')?.setAttribute(
  'content',
  initialTheme === 'dark' ? '#000000' : '#ffffff',
);
