---
id: TQ-0024
title: Collapse albums by default
status: done
priority: normal
labels:
  - frontend
created: 2026-09-20T08:35:21+02:00
updated: 2026-09-20T08:36:08+02:00
---

Start platform, game, and nested album tree rows in the collapsed state. Keep label selection separate from each expansion arrow. Update widget tests.

---

## Notes

- 2026-09-20T08:36:08+02:00 — Platform rows and album rows with children now start collapsed. Label selection does not expand a row. Widget tests cover both platform and game expansion. Flutter analysis: no issues. Tests: 26 passed.
