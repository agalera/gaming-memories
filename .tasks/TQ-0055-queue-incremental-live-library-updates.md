---
id: TQ-0055
title: Queue incremental live library updates
status: done
priority: normal
labels:
  - component/backend
  - component/frontend
created: 2026-09-21T12:59:55+02:00
updated: 2026-09-21T13:17:05+02:00
---

Replace watcher event batching with a serialized background queue of targeted library update operations. File and folder changes should update only affected tree/list/timeline/cache state as each operation completes. Manual Force refresh remains the only full-library recovery scan. Provider collection relies on watcher events to make imported captures appear.

## Done when

- Watcher changes are queued and applied incrementally in the background.
- Folder creation updates the visible tree without waiting for a full-library scan.
- Bursts preserve event ordering and do not trigger a full scan.
- Manual refresh still performs a full scan.
- Regression coverage and make check pass.

---

## Notes

- 2026-09-21T13:17:04+02:00 — Root cause: watcher events were debounced/deduplicated into parent-folder rescans, held behind provider busy state, and notified only after a batch completed. Replaced that path with a FIFO operation queue that runs during provider collection, applies exact file mutations via LibraryScanner.mediaItemAt, inserts/removes folders in the tree immediately, and persists the timeline cache after the queue drains. Manual Refresh remains the only full-library rescan. Added regression coverage for event ordering, immediate folder publication/removal, and updates during provider collection. make check passes: formatting clean, analyzer clean, 182 tests passed.
