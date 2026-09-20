---
id: TQ-0037
title: Generate desktop app icons
status: done
priority: normal
labels:
  - ui
created: 2026-09-20T18:46:42+02:00
updated: 2026-09-20T18:50:07+02:00
---

Use the project logo from Assets to generate and configure application icons for Windows, macOS, and Linux.

---

## Notes

- 2026-09-20T18:50:07+02:00 — Generated the desktop icons from assets/logo.png without a redraw.

  The macOS asset set contains sizes from 16 through 1024 pixels. The Windows ICO contains seven sizes from 16 through 256 pixels. Linux uses a 512-pixel PNG.

  Added make icons for repeatable generation. Added the Linux bundle install rule and GTK window icon setup.

  Verification passed: make icons, Linux debug build, bundle comparison, git diff --check, format check, Flutter analysis, and 122 tests. Three environment tests remain skipped.
