---
id: TQ-0071
title: Save changed settings with debounced text fields
status: done
priority: normal
labels:
  - component/frontend
created: 2026-09-22T11:48:26+02:00
updated: 2026-09-22T12:04:34+02:00
---

Save settings only when a field value has changed. Non-text controls save on a changed value. Text fields save after a debounce and also on blur, without duplicate writes for an unchanged value. Add focused widget coverage and run make check.

---

## Notes

- 2026-09-22T12:04:34+02:00 — Implemented draft-signature dirty tracking in the shared settings autosave path. Repeated values no longer reach validation or ConfigStore; non-text controls flush immediately; text controllers keep the 300 ms debounce and an app focus change flushes the active edit on blur. Added widget coverage for unchanged controls, changed controls, debounce timing, and blur flushing.\n\nVerification: focused tests pass, the complete widget suite passes, fvm flutter analyze reports no issues, and the full 298-test suite passes (one existing rsync-3 test skipped). make check itself stops at format-check because 16 pre-existing TQ-0070 Publish files are unformatted; this task's two changed files pass the same format check and git diff --check passes.
