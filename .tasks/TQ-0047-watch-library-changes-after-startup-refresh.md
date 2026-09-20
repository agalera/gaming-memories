---
id: TQ-0047
title: Watch library changes after startup refresh
status: done
priority: normal
labels:
  - component/backend
  - component/frontend
created: 2026-09-20T22:55:53+02:00
updated: 2026-09-20T23:15:05+02:00
---

Refresh the timeline cache once after startup. Then watch the library folder for file and folder changes. Apply changes to the timeline cache and visible views without a full library scan. Keep manual Refresh as a full recovery action. Add controller and service tests.

---

## Notes

- 2026-09-20T23:14:33+02:00 — Added a native recursive library watcher with per-folder subscriptions for Linux compatibility. The app now starts the watcher before its startup refresh, updates only affected folders or subtrees, reuses unchanged previews, updates open views, and saves one cache update per event batch. Provider scans now rely on watcher events. Manual Refresh remains a full recovery action. Watcher failures do not stop a refresh. Verified with Flutter analysis and the full test suite: 139 passed and 3 skipped. Added focused watcher, controller, scanner, and cache tests.
- 2026-09-20T23:15:05+02:00 — Final verification after the watcher start guard: Flutter analysis passed. The full suite passed with 140 tests and 3 skipped tests.
