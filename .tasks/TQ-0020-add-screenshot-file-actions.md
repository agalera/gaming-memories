---
id: TQ-0020
title: Add screenshot file actions
status: done
priority: high
labels:
  - component/frontend
  - feature
created: 2026-09-20T01:37:54+02:00
updated: 2026-09-20T01:48:22+02:00
---

Add Open in Finder or file manager, Copy image, and Copy path actions to the screenshot detail section. Add the same actions to each gallery card context menu. Use native image clipboard data. Add service and widget coverage.

---

## Notes

- 2026-09-20T01:48:22+02:00 — Added OS-specific file manager labels and launch commands. Added native Copy image support through imclipboard 0.2.2 and text clipboard support for Copy path. Added the same three actions as detail buttons and a ForUI secondary-click menu. Added success and error status messages plus controller and widget coverage. Rejected super_clipboard because its native build required unavailable rustup. All 21 tests, analysis, format checks, and the Linux debug build pass.
