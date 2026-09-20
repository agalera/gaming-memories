---
id: TQ-0032
title: Cache the timeline and add lazy album navigation
status: done
priority: high
labels:
  - feature
  - component/backend
  - component/frontend
created: 2026-09-20T17:32:50+02:00
updated: 2026-09-20T17:49:33+02:00
---

Load the timeline from a disk cache. Refresh that cache in the background. Read platform, game, and sub-album folders only when each view opens. Show game covers, media thumbnails, a navigable breadcrumb, and view actions. Remove media counts from the sidebar.

---

## Notes

- 2026-09-20T17:48:05+02:00 — Added a versioned timeline cache in the application support folder. Startup loads that cache and a folder-only sidebar tree, then runs the full media and thumbnail scan in the background. Platform views show game cover cards. Game and sub-album views read only direct folders and media. Added a navigable breadcrumb and kept refresh and collect actions on the right. Removed sidebar media counts. Added cache, scanner, controller, and widget tests.
- 2026-09-20T17:49:33+02:00 — Verification: make check passed with 117 tests. The Linux debug desktop build also completed successfully.
