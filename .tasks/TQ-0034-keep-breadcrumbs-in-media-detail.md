---
id: TQ-0034
title: Keep breadcrumbs in media detail
status: done
priority: normal
labels:
  - ui
created: 2026-09-20T18:22:26+02:00
updated: 2026-09-20T18:25:27+02:00
---

Keep the active library breadcrumb visible when a media file opens. Remove redundant gallery description text.

---

## Notes

- 2026-09-20T18:25:26+02:00 — Media details now use the active gallery breadcrumb and add the file name as the current item. The current list breadcrumb closes the detail view without a route reload. Removed the redundant page descriptions from gallery views. make check passes with 118 tests and 3 environment skips.
