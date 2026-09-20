---
id: TQ-0039
title: Complete timeline media breadcrumbs
status: done
priority: normal
labels:
  - ui
created: 2026-09-20T19:31:42+02:00
updated: 2026-09-20T19:34:35+02:00
---

When a media file opens from the timeline, show its platform, game, and sub-album path in the breadcrumb. Keep breadcrumb navigation valid.

---

## Notes

- 2026-09-20T19:34:35+02:00 — Timeline media details now derive platform, game, and sub-album breadcrumb items from the selected media. Each derived item navigates to its library view. Long breadcrumbs scroll to the end so the file remains visible.

  Added widget coverage for nested timeline media and folder navigation. Full checks pass with 122 tests and three environment skips.
