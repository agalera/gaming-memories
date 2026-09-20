---
id: TQ-0033
title: Preserve game cover aspect ratios
status: done
priority: normal
labels:
  - component/frontend
created: 2026-09-20T17:53:05+02:00
updated: 2026-09-20T17:57:21+02:00
---

Show each game cover without cropping. Size each game card from the cover aspect ratio.

---

## Notes

- 2026-09-20T17:57:09+02:00 — Replaced the fixed-height game grid with a wrapping card layout. Each cover resolves its file dimensions, sets the card image area to that aspect ratio, and uses BoxFit.contain. Missing or invalid covers use a 16:9 placeholder.
- 2026-09-20T17:57:21+02:00 — Verification: make check passed with 117 tests.
