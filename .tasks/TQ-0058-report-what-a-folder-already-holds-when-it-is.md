---
id: TQ-0058
title: Report what a folder already holds when it is watched
status: done
priority: normal
labels:
  - bug
  - component/backend
created: 2026-09-21T14:09:52+02:00
updated: 2026-09-21T14:09:52+02:00
---

## Problem

The watcher subscribed to a folder that arrived, but never said what was
already inside it. A game folder built elsewhere and moved or copied into the
library — the way an export, a restore or a Finder copy lands — produced one
create event for the folder and nothing for its captures, so the timeline and
the album stayed empty until a Force refresh.

## Fix

The walk that sets up the watch announces every entry it finds as a create,
for folders added in response to an event. The first walk, over the library the
app starts on, stays quiet so startup does not replay the whole library.

---

## Notes

- 2026-09-21T14:09:52+02:00 — Confirmed against the real watcher before fixing: a folder renamed into the library reported only its own create, and nothing for the capture inside it. The controller's directory scan covered the common case by luck of timing, but not a platform-level folder, where _libraryLocationForDirectory returns null and no scan runs.

  addTree now takes announce, passed as true from the create and move handlers and inherited by the recursion; the initial walk over the library leaves it false. Create events also start a watch whenever the change is known to be a directory, not only when the platform flagged the event itself.

  Tests: the watcher reports the folder, its file, its sub-album and the nested file when a staged folder is renamed in, and keeps watching it afterwards; the startup walk announces no files. A controller test moves a staged game folder into the library and expects the game in the platform view and its capture in the timeline. The startup test settles for 500ms first because macOS can still be delivering the events that built the fixture — 12 runs of the watcher suite and 6 of the whole suite were clean.
