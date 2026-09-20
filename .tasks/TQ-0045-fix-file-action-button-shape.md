---
id: TQ-0045
title: Fix file action button shape
status: done
priority: normal
labels:
  - component/frontend
created: 2026-09-20T21:31:51+02:00
updated: 2026-09-20T21:38:37+02:00
---

Remove the layout artifact below file action buttons in the content header. Keep all action buttons visually consistent with ForUI pill buttons.

---

## Notes

- 2026-09-20T21:34:32+02:00 — User clarified that file actions must match the other ForUI outline buttons, not use a custom pill style. Kept the standard outline style and removed the nested Flexible text widgets that changed their header layout.
- 2026-09-20T21:38:37+02:00 — The screenshot showed the same bottom tab on every file action button. The ForUI RoundedSuperellipseBorder caused the render defect. Converted only the action decoration to BoxDecoration, which preserves the ForUI radius, border, colors, and state variants. Added a widget test for the rounded rectangle decoration.
