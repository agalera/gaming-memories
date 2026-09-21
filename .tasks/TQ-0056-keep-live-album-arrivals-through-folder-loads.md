---
id: TQ-0056
title: Keep live album arrivals through folder loads
status: done
priority: normal
labels:
  - bug
  - component/frontend
created: 2026-09-21T13:30:30+02:00
updated: 2026-09-21T13:33:06+02:00
---

## Problem

A capture that lands in the album being viewed shows up, then disappears: the
folder load and the preview pass publish the snapshot they started from, which
does not know about anything the watcher applied since. The timeline keeps the
capture, the open album loses it until it is reopened.

## Fix

Record what the live queue does to the visible listing for the current folder
request, and re-apply those edits to every snapshot the load or the preview
pass publishes.

## Done when

- A file that arrives while an album's previews are being prepared stays in the
  list.
- A file removed live does not come back when the preview pass publishes.
- Navigating to another album starts from a clean slate.
- make check passes.

---

## Notes

- 2026-09-21T13:33:06+02:00 — The album list already grew per file, but every snapshot published by the folder load and by the preview pass replaced the whole listing, so anything the watcher had applied since the load started was wiped — a capture arriving while previews were being prepared appeared and then vanished, while the timeline kept it.

  The controller now records the live edits made to the visible listing for the current folder request (upserted media, added folders, removed paths) and replays them over every snapshot the load or the preview pass publishes. The record is cleared when a load starts and when navigation swaps the listing, so another album's edits are never replayed.

  Covered by two regression tests that hold the preview pass open while a watched create and a watched delete land. make check passes with 184 tests.
