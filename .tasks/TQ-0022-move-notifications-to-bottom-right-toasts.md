---
id: TQ-0022
title: Move notifications to bottom-right toasts
status: done
priority: normal
labels:
  - frontend
created: 2026-09-20T08:21:16+02:00
updated: 2026-09-20T08:27:01+02:00
---

Replace page progress and status banners with ForUI toast components. Show progress in one persistent bottom-right toast. Show success and error results as timed bottom-right toasts. Add widget tests for position, progress, success, and error states.

---

## Notes

- 2026-09-20T08:27:01+02:00 — Replaced the page banners with ForUI bottom-right toasts. Progress uses one persistent toast with the current message and percentage. Success and error results use timed toasts. Error toasts use the destructive variant. Added a notification revision so repeated messages still appear. Flutter analysis: no issues. Tests: 26 passed.
