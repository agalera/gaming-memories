---
id: TQ-0018
title: Generate persistent gallery thumbnails
status: done
priority: high
labels:
  - component/backend
  - component/frontend
  - feature
created: 2026-09-20T01:25:36+02:00
updated: 2026-09-20T01:29:17+02:00
---

Create compatible .thumb.jpg files for gallery images. Generate missing thumbnails during each library scan. Replace stale thumbnails when the source file changes. Exclude thumbnail files from albums. Make gallery cards load the thumbnail path. Add scan and widget coverage.

---

## Notes

- 2026-09-20T01:29:17+02:00 — Added compatible <image>.thumb.jpg sidecars with a 360-pixel limit and JPEG quality 85. Library scans create missing thumbnails and replace stale thumbnails. Gallery cards load sidecars and fall back to originals. Sidecars stay outside album results. All 17 tests, analysis, format checks, and the Linux debug build pass.
