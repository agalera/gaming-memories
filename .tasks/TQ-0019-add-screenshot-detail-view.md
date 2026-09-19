---
id: TQ-0019
title: Add screenshot detail view
status: done
priority: high
labels:
  - component/frontend
  - feature
created: 2026-09-20T01:32:16+02:00
updated: 2026-09-20T01:36:40+02:00
---

Open a screenshot detail section from each gallery card. Show the full image and file details. Add a back action that restores the exact gallery filter and scroll offset. Keep gallery cards on thumbnail files. Add controller and widget coverage.

---

## Notes

- 2026-09-20T01:36:40+02:00 — Made each gallery card selectable. Added a responsive detail section with the original image, zoom support, and file details. Added a nested header with a back action. Kept the gallery mounted in an IndexedStack, which preserves its filter, ScrollPosition, and exact offset. Added controller and widget coverage. All 19 tests and the Linux debug build pass.
