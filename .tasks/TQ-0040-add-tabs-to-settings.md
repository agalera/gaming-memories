---
id: TQ-0040
title: Add tabs to settings
status: done
priority: normal
labels:
  - ui
created: 2026-09-20T19:37:34+02:00
updated: 2026-09-20T19:58:43+02:00
---

Replace the long settings list with tabs. Give library settings and each provider a separate section. Keep all current controls and save behavior.

---

## Notes

- 2026-09-20T19:42:47+02:00 — Replaced the long settings list with nine scrollable ForUI tabs: General and one tab for each provider. Only the selected settings card remains visible. All existing controls and autosave behavior remain intact.

  Updated widget tests to select the correct tab. Added coverage for every provider tab. Full checks pass with 122 tests and three environment skips.
- 2026-09-20T19:43:57+02:00 — User feedback: use only Appearance, Library, and Providers tabs. Show providers as expandable cards with a logo placeholder, name, and enable switch. Reject activation when provider validation fails. Remove the autosave note.
- 2026-09-20T19:58:43+02:00 — Replaced the nine-tab layout with Appearance, Library, and Providers tabs. Providers now appear as collapsed cards with placeholder icons, independent expand controls, and enable switches. Disabled providers remain configurable. Activation now validates folder paths and provider-specific settings. Steam verifies online credentials before activation. Invalid providers stay disabled and show an inline error. Removed the automatic-save note. Added widget and Steam validation tests. Full make check passes with 125 tests and three environment skips.
