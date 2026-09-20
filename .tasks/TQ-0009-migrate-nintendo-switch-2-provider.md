---
id: TQ-0009
title: Migrate Nintendo Switch 2 provider
status: done
priority: normal
labels:
  - feature
  - component/backend
depends_on:
  - TQ-0001
created: 2026-09-19T23:38:21+02:00
updated: 2026-09-20T17:24:45+02:00
---

Migrate local album and MTP collection, ignored folders, clips, requirements, settings, and tests.

---

## Notes

- 2026-09-20T15:38:18+02:00 — Mapped the original provider. The migration will preserve both modes: a custom copied-album folder on any platform, or direct Linux USB/MTP collection through mtp-folders, mtp-files, and mtp-connect. It will keep only _s JPG/MP4 captures, preserve console filenames, skip configured album folders and already-imported device captures, verify MTP transfer sizes, and surface actionable warnings for missing tools, busy/stale sessions, and absent consoles.
- 2026-09-20T15:49:33+02:00 — Implemented copied-album and direct Linux USB/MTP collection. The provider imports original _s JPG screenshots and MP4 clips, preserves console names, skips _c copies, ignored folders, and already-imported device captures, batches mtp-connect transfers, verifies transferred sizes, handles real sysfs symlinks, cleans staging files, and gives actionable warnings for missing libmtp tools, absent devices, busy devices, and stale sessions. Added autosaved settings, macOS folder grants for copied albums, documentation, and parser/provider/config/controller/widget tests.
- 2026-09-20T15:49:33+02:00 — Verification complete: make check passed formatting, static analysis, and all 112 tests; the macOS debug application also built successfully; git diff --check is clean.
- 2026-09-20T17:24:45+02:00 — Pre-commit verification repeated after documenting cross-platform MTP follow-up TQ-0029: make check passed formatting, static analysis, and all 114 tests.
