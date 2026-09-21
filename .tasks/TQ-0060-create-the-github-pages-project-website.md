---
id: TQ-0060
title: Create the GitHub Pages project website
status: done
priority: normal
labels:
  - feature
  - component/frontend
  - component/ci
  - docs
created: 2026-09-21T20:17:44+02:00
updated: 2026-09-21T21:22:44+02:00
---

Build a polished static website for Gaming Memories. Add a project overview, real application screenshots, a current release download link, user documentation, responsive layouts, and the GitHub Pages deployment workflow.\n\n## Done when\n\n- The landing page explains the project and its main features.\n- The site links to the latest release and selects a useful download for the current platform.\n- The site includes setup and provider documentation.\n- The site uses real application screenshots or accurate application previews.\n- GitHub Actions can publish the static site to GitHub Pages.\n- Local checks for links, HTML, CSS, and JavaScript pass.

---

## Notes

- 2026-09-21T20:17:51+02:00 — Started the static site. The project has no screenshot assets, so the site will use accurate CSS previews based on the current Flutter interface. The release button will resolve the current release through the GitHub API and keep the releases page as its fallback.
- 2026-09-21T20:59:12+02:00 — The first visual direction felt too generic. Replaced the dark gradient and card-heavy concept with a simpler archive design: warm paper tones, crisp rules, square photo frames, strong typography, and a contact-sheet layout.
- 2026-09-21T21:13:35+02:00 — Finished the archive-style redesign. Added a responsive landing page, detailed documentation, sample interface previews, direct release resolution, local asset checks, README links, and a GitHub Pages deployment workflow. Verification passed: node tool/check_site.mjs, node --check site/app.js, workflow YAML parse, and git diff --check. Browser control was unavailable, so no automated browser screenshot was possible.
- 2026-09-21T21:14:32+02:00 — The second direction still kept too much of the first page structure. Started a full layout reset. The new direction uses a small centered hero, one product preview, three rounded feature cards, a compact source list, and one download panel.
- 2026-09-21T21:22:44+02:00 — Completed the third design direction as a full structure reset. The landing page now uses a centered hero, one rounded product preview, three feature cards, one setup panel, source pills, and one download panel. It removes the archive numbering, contact sheet, fact strip, and large editorial sections. Updated the documentation style and social preview to match. Site checks pass.
