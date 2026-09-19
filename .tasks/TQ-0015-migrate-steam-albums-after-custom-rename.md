---
id: TQ-0015
title: Migrate Steam albums after custom rename
status: done
priority: high
labels:
  - component/backend
  - feature
created: 2026-09-20T01:09:50+02:00
updated: 2026-09-20T01:11:34+02:00
---

When a Steam custom game name differs from the store name, move the existing album to the custom name. Merge existing destination files without data loss. Add provider tests.

---

## Notes

- 2026-09-20T01:11:34+02:00 — Steam collection now resolves each custom app ID to its store name before import. It renames an existing store-name album or merges its files into the custom-name album. Identical files collapse, conflicting screenshots get hash suffixes, and an existing custom cover wins. Added rename and merge tests. All 16 tests and the Linux debug build pass.
