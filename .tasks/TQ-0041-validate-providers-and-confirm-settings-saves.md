---
id: TQ-0041
title: Validate providers and confirm settings saves
status: done
priority: normal
labels:
  - ui
created: 2026-09-20T20:00:01+02:00
updated: 2026-09-20T20:06:46+02:00
---

Validate enabled providers during app startup and each settings save. Disable any provider whose configuration fails. Sort provider cards by name in ascending order. Show a toast after settings save.

---

## Notes

- 2026-09-20T20:06:46+02:00 — Added one provider validation path in LibraryController. It runs during startup, settings saves, and folder selection. Invalid enabled providers are saved as disabled and produce a warning. Settings saves now create success toasts. Provider cards now sort by name in ascending order. The settings form reflects provider states after validation. Steam caches a successful credential check for the active credential pair. Added controller and widget coverage. Full make check passes.
