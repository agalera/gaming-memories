---
id: TQ-0046
title: Show library operation progress in sidebar buttons
status: done
priority: normal
labels:
  - component/frontend
created: 2026-09-20T22:43:26+02:00
updated: 2026-09-20T22:51:38+02:00
---

Replace the persistent progress toast for library refresh and provider scan operations. Show a spinner and progress state inside the related sidebar button. Keep result notifications on the bottom-right corner. Add widget coverage for both button states.

---

## Notes

- 2026-09-20T22:51:38+02:00 — User replaced the bottom-left toast request with button-based progress. Removed the persistent progress toast. Refresh now shows a spinner and Refreshing label. Scan now shows a spinner plus its percentage when available. Operation result toasts remain at the bottom right. Full make check passes with 136 tests and three expected skips.
