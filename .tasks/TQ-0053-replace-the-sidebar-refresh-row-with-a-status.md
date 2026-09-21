---
id: TQ-0053
title: Replace the sidebar refresh row with a status toast
status: done
priority: normal
labels:
  - feature
  - component/frontend
  - ui
created: 2026-09-21T11:58:39+02:00
updated: 2026-09-21T12:30:37+02:00
---

## Goal

The sidebar footer refresh row becomes a library status surface: an inline
toast-like panel on the left and a small icon-only force refresh button on the
right.

## Scope

- `LibraryController` exposes a `LibraryActivity` describing what the library is
  doing right now: scanning, refreshing, applying watched changes, changes
  detected and waiting, or idle.
- Watched changes report what they did — media added, removed and updated —
  and the summary stays visible for a few seconds after the update lands.
- A `LibraryStatusToast` widget renders that activity with an icon, a title, a
  detail line and a progress bar (determinate when the operation reports a
  value).
- The force refresh button keeps its behaviour and becomes icon-only, with a
  hover tooltip.

---

## Notes

- 2026-09-21T12:04:22+02:00 — The footer row is now a LibraryStatusToast plus an icon-only force refresh button with a 'Force refresh' tooltip.

  LibraryController.libraryActivity resolves, most urgent first: scanning (determinate bar from progressValue), refreshing (indeterminate bar, no detail since the progress message only repeated the title), applying watched changes, changes waiting behind a running operation, no library folder or missing access, the last change summary, then the capture count.

  Watched changes report added/removed/updated by diffing the timeline keys before and after a batch; the summary stays for 8 seconds. Queue events notify listeners on a 200ms timer so a large copy does not rebuild the shell per file.
- 2026-09-21T12:29:25+02:00 — Follow-up: disable Force refresh while a watcher-driven library update is running, and match the button height to the adjacent status pill.
- 2026-09-21T12:30:37+02:00 — Follow-up implemented: Force refresh now uses LibraryActivity.isRunning, so watcher-driven updates disable the button along with scans and full refreshes. Wrapped the status/button row in IntrinsicHeight with stretched children so their rendered heights match even for the taller updating state. Added a widget regression test for both requirements. make check passes with 180 tests.
