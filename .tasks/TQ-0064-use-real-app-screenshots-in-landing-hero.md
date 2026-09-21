---
id: TQ-0064
title: Use real app screenshots in landing hero
status: done
priority: normal
labels:
  - feature
  - component/frontend
created: 2026-09-21T22:33:23+02:00
updated: 2026-09-21T22:50:57+02:00
---

Replace the landing page's simulated app preview with the supplied screenshot pairs. Show the light or dark version that matches the active website theme and rotate through timeline, game list, and image list with a fade every 10 seconds.\n\n## Done when\n\n- The landing hero uses the supplied real screenshots.\n- Light and dark website themes select matching screenshot variants.\n- The three views crossfade automatically every 10 seconds.\n- Reduced-motion visitors see a stable screenshot.\n- Site checks pass.

---

## Notes

- 2026-09-21T22:40:45+02:00 — Replaced the simulated landing-page preview with the supplied timeline, game-list, and image-list screenshot pairs. Added theme-aware light/dark variants, a 10-second crossfade, a pause control, visibility-aware timing, and a stable reduced-motion state. Exported web-ready copies at 2.3 MB total while preserving the original source images. Verification passed: JavaScript syntax checks, site reference checks, and git diff checks.
- 2026-09-21T22:43:56+02:00 — Follow-up refinement: removed the screenshot border and deleted the caption/pause-control row. The theme-aware 10-second crossfade and reduced-motion behavior remain unchanged. Site and JavaScript checks pass.
- 2026-09-21T22:50:52+02:00 — Fixed the light-theme black frame. Root cause: the screenshot files have transparent outer padding, and the carousel forced a black background behind that transparency. Removed the carousel background and its extra box shadow, then added a site check preventing future backgrounds behind the transparent screenshot canvas. The focused repro and all site checks now pass.
