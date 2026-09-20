---
id: TQ-0004
title: Migrate Hytale provider
status: done
priority: normal
labels:
  - feature
  - component/backend
depends_on:
  - TQ-0001
created: 2026-09-19T23:38:21+02:00
updated: 2026-09-20T13:50:08+02:00
---

Migrate Hytale screenshot discovery, bundled cover behavior, settings, and tests.

---

## Notes

- 2026-09-20T13:50:08+02:00 — Implemented Hytale automatic discovery on macOS/Linux, custom folders, persistent macOS folder grants, autosaved settings, PNG/JPEG import, and the bundled cover.png asset. Added provider, settings, path, permission, persistence, asset, and widget coverage. Verified with make check (57 tests) and a successful macOS debug build.
