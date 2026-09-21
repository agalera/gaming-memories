---
id: TQ-0054
title: Turn Scan into a rich progress action
status: done
priority: normal
labels:
  - component/frontend
  - ui
created: 2026-09-21T12:32:20+02:00
updated: 2026-09-21T12:37:14+02:00
---

Replace the sidebar Scan button's text-only busy state with a toast-style action surface. It remains clickable while idle and becomes disabled during collection while showing current provider/game detail and determinate or indeterminate progress.

## Done when

- Idle Scan remains an obvious action.
- Active collection shows the current work and a progress bar inside the same control.
- The rich Scan surface fits the sidebar footer and is covered by widget tests.
- make check passes.

---

## Notes

- 2026-09-21T12:37:14+02:00 — Implemented a dedicated LibraryScanActivity and LibraryScanToast. The sidebar Scan row now mirrors Force refresh: a toast-style surface plus a same-height icon button. Idle copy explains the action; active scans show the provider/game progress message and a determinate or indeterminate progress bar. Scan and refresh actions block each other and both block during watcher/full-refresh work. Library status no longer duplicates provider scan progress, so it can independently show queued watcher changes. Added controller and widget assertions, including current-game detail, progress value, disabled action, and equal heights. make check passes with 180 tests.
