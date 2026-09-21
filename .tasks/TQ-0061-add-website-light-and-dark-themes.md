---
id: TQ-0061
title: Add website light and dark themes
status: done
priority: normal
labels:
  - feature
  - component/frontend
created: 2026-09-21T21:48:11+02:00
updated: 2026-09-21T21:54:22+02:00
---

Add light and dark theme support to the GitHub Pages website. Use white as the main light background and black as the main dark background. Follow the system theme by default. Add a theme switch to both pages and save the visitor choice.\n\n## Done when\n\n- Both pages support light and dark themes.\n- The default theme follows the system preference.\n- The theme switch saves an explicit choice.\n- The main backgrounds and text use standard black and white colors.\n- The site checks pass.

---

## Notes

- 2026-09-21T21:54:22+02:00 — Added system-aware light and dark themes. Light mode uses pure white and black. Dark mode uses pure black and white. Added a saved theme switch to the landing page and documentation. Added an early theme script to prevent the wrong initial theme. Updated the browser theme color and the Pages checks. Verification passed for scripts, links, theme structure, workflow YAML, and git diff checks. Browser control had no available browser, so automated visual review was unavailable.
