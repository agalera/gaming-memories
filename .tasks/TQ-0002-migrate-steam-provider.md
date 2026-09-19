---
id: TQ-0002
title: Migrate Steam provider
status: done
priority: high
labels:
  - feature
  - component/backend
depends_on:
  - TQ-0001
created: 2026-09-19T23:38:21+02:00
updated: 2026-09-20T00:08:55+02:00
---

Migrate local and online Steam screenshots, game name resolution, covers, ignored games, and custom game names. Add all provider fields to Settings.

---

## Notes

- 2026-09-20T00:08:55+02:00 — Added Steam local and online screenshot imports, name resolution, covers, ignored app IDs, custom names, cache support, and all active Steam settings. Refactored provider collection through a shared interface. Verified with 11 tests, static analysis, format checks, and a Linux debug build.
