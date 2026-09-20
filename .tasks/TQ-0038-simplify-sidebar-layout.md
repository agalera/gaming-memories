---
id: TQ-0038
title: Simplify sidebar layout
status: done
priority: normal
labels:
  - ui
created: 2026-09-20T18:55:38+02:00
updated: 2026-09-20T19:29:38+02:00
---

Remove the app title and placeholder logo from the sidebar. Remove the Library and Albums section labels. Show all navigation items in one list. Remove extra vertical space around the horizontal separator.

---

## Notes

- 2026-09-20T18:59:08+02:00 — Removed the sidebar title and placeholder logo. Replaced the Library and Albums groups with one unlabeled navigation group. Set the footer divider margin to zero.

  Verification passed: widget tests, format check, Flutter analysis, and 122 tests. Three environment tests remain skipped.
- 2026-09-20T19:03:30+02:00 — User feedback: make the separator the exact footer limit. Replace the divider with a top border on the bottom button area.
- 2026-09-20T19:06:21+02:00 — Replaced the footer divider with a top border on the footer. The border now sits at the exact limit between the album list and the buttons.

  Removed the gallery outer space on the right and bottom. Added 24 pixels of right space inside the scroll content, so the viewport reaches the edge.

  Verification passed: widget tests, format check, Flutter analysis, and 122 tests. Three environment tests remain skipped.
- 2026-09-20T19:08:07+02:00 — User feedback: remove all bottom space from the album list. Override the ForUI content, group, and footer defaults.
- 2026-09-20T19:10:21+02:00 — Removed the remaining ForUI bottom space from the album list. The content bottom padding, group bottom padding, and footer outer padding are zero. The footer has no divider widget and uses its own top border.

  Added a resize handle on the sidebar right edge. The width starts at 256 pixels and stays between 220 and 480 pixels.

  Verification passed: widget tests, format check, Flutter analysis, and 122 tests. Three environment tests remain skipped.
- 2026-09-20T19:24:31+02:00 — User feedback: the folder view still has too much right space. Reduce the gallery content right padding from 24 to 8 pixels.
- 2026-09-20T19:25:02+02:00 — Reduced the gallery content right padding from 24 to 8 pixels. Full checks pass with 122 tests and three environment skips.
- 2026-09-20T19:26:17+02:00 — Found the game-list gap cause. The card width uses the full viewport, but the sliver later removes right padding. Multiple cards therefore cannot fit in the calculated row.
- 2026-09-20T19:27:43+02:00 — Corrected the game card column calculation. It now subtracts the internal right padding before it selects the column count and card width. Added a multi-column layout test.

  Restored 24 pixels of right padding to match the left side and leave room for the scroll bar. Full checks pass with 122 tests and three environment skips.
- 2026-09-20T19:28:33+02:00 — User feedback: add bottom padding inside the sidebar button container. Use 12 pixels to match its top padding.
- 2026-09-20T19:29:38+02:00 — Added 12 pixels below the sidebar footer buttons. This matches the existing top padding. Full checks pass with 122 tests and three environment skips.
