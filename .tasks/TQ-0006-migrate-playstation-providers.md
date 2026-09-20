---
id: TQ-0006
title: Migrate PlayStation providers
status: done
priority: normal
labels:
  - feature
  - component/backend
depends_on:
  - TQ-0001
created: 2026-09-19T23:38:21+02:00
updated: 2026-09-20T14:17:05+02:00
---

Migrate PlayStation 4 and PlayStation 5 screenshots, clips, recordings, metadata tools, settings, and tests.

---

## Notes

- 2026-09-20T14:17:05+02:00 — Implemented PlayStation 4 and PlayStation 5 folder-backed providers. Both use custom exported-media folders with settings-time validation and macOS security-scoped grants. PS4 imports JPG dates through ExifTool and MP4 dates from filenames; PS5 imports JPG/WEBM dates from filenames and subtracts optional FFprobe duration for clip start time. Undated media keeps its source name under Other, duplicates retain collision-safe hashes, and hidden/unsupported files are ignored. Added schema v9 persistence, provider settings cards, parser/provider/config/controller tests, README documentation, and read-only-safe FFprobe duration handling. Verified with make check (86 tests) and fvm flutter build macos --debug.
