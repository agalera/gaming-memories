---
id: TQ-0007
title: Migrate Battle.net provider
status: done
priority: normal
labels:
  - feature
  - component/backend
depends_on:
  - TQ-0001
created: 2026-09-19T23:38:21+02:00
updated: 2026-09-20T14:34:06+02:00
---

Replace the standalone Diablo IV provider with one Battle.net provider that detects installed Diablo IV and World of Warcraft variants, imports screenshots into their existing PC/<game> albums, migrates Diablo IV settings and folder grants, supports automatic and custom roots with macOS persistent access, converts supported TGA screenshots for the gallery, and adds catalog, provider, settings, migration, and discovery tests.

---

## Notes

- 2026-09-20T14:34:06+02:00 — Implemented one Battle.net provider replacing standalone Diablo IV. It parses product.db without a new dependency, discovers Diablo IV and World of Warcraft variants, keeps per-game PC albums, converts WoW TGA captures to PNG, migrates legacy settings and folder grants, and supports custom and persistent macOS automatic roots. Verification: make check passed (format, analyzer, 94 tests) and fvm flutter build macos --debug produced Gaming Memories.app.
