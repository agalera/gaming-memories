---
id: TQ-0036
title: Show album tree load progress
status: done
priority: normal
labels:
  - ui
created: 2026-09-20T18:32:35+02:00
updated: 2026-09-20T18:45:46+02:00
---

Show a compact spinner in the sidebar album area while the startup folder tree loads. Document the folder tree source in the task notes.

---

## Notes

- 2026-09-20T18:40:31+02:00 — The startup controller previously waited for both the folder tree and timeline cache before it published either result. It now publishes the folder tree as soon as that scan ends. Timeline cache decode, item conversion, and sorting now run in an isolate. The sidebar uses a separate album tree state and shows a compact spinner only while that scan is active. make check passes with 120 tests and 3 environment skips.
- 2026-09-20T18:42:24+02:00 — User verification showed that the album list still appeared with the timeline. The remaining cause is the recursive startup tree scan, which enumerates every media entry while it searches for sub-albums. Replace it with a shallow startup tree and lazy sub-album scans.
- 2026-09-20T18:45:46+02:00 — The first fix only separated tree publication from timeline cache completion. It did not remove the recursive tree scan. The startup scan is now shallow and reads only platform folders, game folders, and cover paths. A game arrow loads that game's sub-album tree on demand and shows its own spinner. Sub-album paths are now relative to the game folder. make check passes with 122 tests and 3 environment skips.
