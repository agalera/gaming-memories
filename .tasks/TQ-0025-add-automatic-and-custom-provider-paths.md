---
id: TQ-0025
title: Add automatic and custom provider paths
status: done
priority: high
labels:
  - component/frontend
  - component/backend
created: 2026-09-20T10:07:19+02:00
updated: 2026-09-20T10:30:45+02:00
---

Let each provider use automatic path discovery by default, with an opt-in custom path control. Validate custom paths in Settings, save valid edits immediately without a Save button, and prevent invalid paths from surfacing later during library scans. Add model, controller, provider, persistence, and widget coverage.

---

## Notes

- 2026-09-20T10:20:10+02:00 — Added explicit automatic/custom path modes for Diablo IV, Guild Wars 2, and Steam with legacy auto-path migration. Settings now show custom folder pickers conditionally, validate folders inline on entry and edit, autosave all valid changes after a short debounce, preserve the last saved path when a draft is invalid, and no longer have a Save button or rescan after every settings edit. make check passes: formatting, analysis, and 34 tests. Linux debug build could not run on the macOS host; existing unrelated macOS runner changes were left untouched.
- 2026-09-20T10:22:14+02:00 — Follow-up: automatic discovery currently throws an error when Diablo IV or Guild Wars 2 is not installed. Change missing auto-discovered sources into processing warnings and remove raw empty-path details from user-facing messages.
- 2026-09-20T10:26:56+02:00 — Follow-up fixed: providers had represented unavailable automatic discovery with FileSystemException, which aborted collection and appended path = '' to the toast. Diablo IV and Guild Wars 2 now return structured skipped-provider warnings when auto discovery finds no installation. Collection continues across providers, aggregates warnings, and shows an auto-dismissing non-destructive alert toast. Custom-path/tool/I/O failures remain errors. Added controller and widget regressions. make check passes formatting, analysis, and 36 tests.
- 2026-09-20T10:27:45+02:00 — Follow-up: render warnings with their own color treatment and emit one warning toast per unavailable provider instead of aggregating providers into one message.
- 2026-09-20T10:30:45+02:00 — Warnings now use a bounded notification event queue, so every unavailable provider produces its own toast instead of being merged into one message. Warning icon/title/description use amber (#B45309 light, #FBBF24 dark), remain non-destructive, and auto-dismiss. Success and error behavior remains unchanged. Added controller fan-out and widget color/toast coverage. make check passes analysis and 36 tests.
