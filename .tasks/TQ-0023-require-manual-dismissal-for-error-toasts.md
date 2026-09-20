---
id: TQ-0023
title: Require manual dismissal for error toasts
status: done
priority: normal
labels:
  - frontend
created: 2026-09-20T08:29:08+02:00
updated: 2026-09-20T08:30:32+02:00
---

Keep error toasts visible until the user closes or swipes them. Add an explicit close button. Keep success toasts timed. Add a widget test for the persistent error state and close action.

---

## Notes

- 2026-09-20T08:30:32+02:00 — Error toasts now use no automatic duration. Each error toast has a close button and retains swipe dismissal. The test confirms that an error remains after six seconds and disappears after the close action. Flutter analysis: no issues. Tests: 26 passed.
