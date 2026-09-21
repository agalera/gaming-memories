---
id: TQ-0059
title: Fix Battle.net folder selection
status: done
priority: high
labels:
  - bug
  - component/frontend
  - component/backend
created: 2026-09-21T17:50:24+02:00
updated: 2026-09-21T17:52:25+02:00
---

Replace the stale folder access label on plain-path platforms. Save each selected Battle.net custom folder in its game setting. Add regression tests for both behaviors.

---

## Notes

- 2026-09-21T17:52:25+02:00 — Fixed the plain-path button label and the per-game Battle.net settings update. Added controller and widget regression tests. make check passes: formatting, analysis, and 187 tests passed with 3 skipped.
