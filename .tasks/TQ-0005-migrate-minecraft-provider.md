---
id: TQ-0005
title: Migrate Minecraft provider
status: done
priority: normal
labels:
  - feature
  - component/backend
depends_on:
  - TQ-0001
created: 2026-09-19T23:38:21+02:00
updated: 2026-09-20T14:03:57+02:00
---

Migrate Minecraft launcher and Flatpak screenshot discovery, settings, and tests.

---

## Notes

- 2026-09-20T14:03:57+02:00 — Implemented Minecraft custom and automatic screenshot collection for the Windows, macOS, Linux launcher, and both supported Linux Flatpak paths. Added autosaved settings, persistent macOS folder grants, provider registration, documentation, and provider/path/controller/widget coverage. Verified with make check (66 tests) and a successful macOS debug build.
