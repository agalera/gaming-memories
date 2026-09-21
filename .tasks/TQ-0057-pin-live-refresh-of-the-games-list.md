---
id: TQ-0057
title: Pin live refresh of the games list
status: done
priority: normal
labels:
  - tests
  - component/frontend
created: 2026-09-21T13:41:14+02:00
updated: 2026-09-21T13:41:14+02:00
---

## Finding

The games list already refreshes live. Probed end to end against the real
macOS watcher: a game folder and its first capture land while the platform
view is open, and the card, the media and a following burst all appear with no
full scan. A new platform and a folder removal do the same.

What was missing was coverage, so nothing pinned the behaviour.

## Done when

- A controller test drives a watched game folder, a watched platform and a
  watched removal through the platform view without a second scan.
- A widget test pins that a game arriving in the tree paints a card in the open
  games list, and that a removed one disappears.
- make check passes.

---

## Notes

- 2026-09-21T13:41:14+02:00 — Probed the real NativeLibraryWatcher on macOS: a created folder reports isDirectory=true, and a capture written into it right after is picked up by the controller's directory scan, so the games list and the timeline both fill in. Also checked the widget layer: gameFolders feeds MediaGallery.games on every rebuild and the cards are keyed by folder path, so the list repaints as the tree changes.

  One narrow hole is left in the watcher, not fixed here: it subscribes to a newly created folder asynchronously and emits nothing for entries that are already inside it, so a file written in that window has no event of its own. The controller's mediaTree scan for a directory create covers it in practice, and Force refresh is the recovery path.
