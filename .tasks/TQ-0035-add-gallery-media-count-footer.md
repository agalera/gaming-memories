---
id: TQ-0035
title: Add gallery media count footer
status: rejected
priority: normal
labels:
  - ui
created: 2026-09-20T18:26:29+02:00
updated: 2026-09-20T18:31:57+02:00
---

Show file, image, and video totals in a fixed footer below the gallery list. Remove the current count badge from the gallery header.

---

## Notes

- 2026-09-20T18:28:13+02:00 — Moved the media totals below the scroll area. The footer shows file, image, and video counts. The folder load progress indicator now uses the footer. Added widget coverage for mixed media counts and footer placement. make check passes with 118 tests and 3 environment skips.
- 2026-09-20T18:29:40+02:00 — The user rejected the footer because it uses too much space. Remove the count footer and keep only a compact load indicator.
