---
id: TQ-0003
title: Migrate Guild Wars 2 provider
status: done
priority: normal
labels:
  - feature
  - component/backend
depends_on:
  - TQ-0001
created: 2026-09-19T23:38:21+02:00
updated: 2026-09-20T09:25:01+02:00
---

Migrate Guild Wars 2 screenshot discovery, date metadata, requirements, settings, and tests.

---

## Notes

- 2026-09-20T09:25:01+02:00 — Added the Guild Wars 2 provider, settings, and main app registration. It scans JPG files from the configured folder or the Windows default folder. It reads FileModifyDate through ExifTool without a timezone shift. It reports a clear requirement error when ExifTool is absent. It preserves capture timestamps and duplicate protection. Flutter analysis: no issues. Tests: 31 passed.
