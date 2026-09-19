---
id: TQ-0013
title: Improve Steam ignored games editor
status: done
priority: normal
labels:
  - component/frontend
  - feature
created: 2026-09-20T00:33:18+02:00
updated: 2026-09-20T00:57:41+02:00
---

Replace the Steam ignored app ID text area with an app ID field, an Add button, and a removable list. Keep settings persistence compatible and add widget coverage.

---

## Notes

- 2026-09-20T00:38:26+02:00 — Replaced the Steam ignored IDs text area with a single-ID field, Add button, and removable list. Existing ignored IDs load into the list and save through the same settings field. Added widget coverage. All 14 tests, analysis, format checks, and the Linux debug build pass.
- 2026-09-20T00:42:17+02:00 — Aligned each Add button with its text fields by placing help text below the input row. Replaced the custom-games text area with app-ID and game-name fields, an Add button, and a removable list. The widget test verifies both list editors and their alignment. All 14 tests and the Linux debug build pass.
- 2026-09-20T00:57:41+02:00 — Changed custom-game editor state from a map to an entry list, so the editor retains several rows before save. Save converts the full list to the provider map. Extended the widget test to add two new games, keep both visible, remove another game, and save both entries.
