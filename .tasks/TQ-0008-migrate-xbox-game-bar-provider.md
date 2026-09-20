---
id: TQ-0008
title: Migrate Xbox Game Bar provider
status: rejected
priority: normal
labels:
  - feature
  - component/backend
depends_on:
  - TQ-0001
created: 2026-09-19T23:38:21+02:00
updated: 2026-09-20T15:26:40+02:00
---

Migrate Windows Xbox Game Bar screenshot discovery, date metadata, settings, and tests.

---

## Notes

- 2026-09-20T14:53:53+02:00 — Implemented the Xbox Game Bar provider and settings around Windows Videos/Captures with a custom-folder fallback. The embedded metadata reader is dependency-free: PNG supports current Game DVR JSON plus legacy EXIF text, and MP4 reads Microsoft Xtra or QuickTime item-list titles plus the media-header date without loading video payloads. Confirmed the legacy path against a real public Game DVR PNG and added provider, parser, path, config, controller, and UI tests.
- 2026-09-20T14:56:12+02:00 — Verification complete: make check passed (format, analyzer, 104 tests), the macOS debug app built successfully, and git diff --check is clean. The metadata parser was also exercised against a real public legacy Game DVR PNG.
- 2026-09-20T15:26:01+02:00 — Xbox Game Bar support was removed by product decision. Its implementation had not been staged or committed, so the working-tree changes were discarded; no historical code commit required reverting.
- 2026-09-20T15:26:40+02:00 — Rejected as out of scope because the user no longer uses Xbox Game Bar.
