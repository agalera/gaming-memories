---
id: TQ-0050
title: Refactor project README
status: done
priority: normal
labels:
  - docs
created: 2026-09-21T10:23:54+02:00
updated: 2026-09-21T10:27:43+02:00
---

Refresh README.md with the project logo and a more attractive, scannable structure inspired by the Worldhopper README. Preserve accurate setup, requirements, provider, and verification information.

---

## Notes

- 2026-09-21T10:25:29+02:00 — Using the Worldhopper README's centered logo/title/tagline/badge header and scannable section hierarchy. Omitting its license and contribution claims because this repository has no LICENSE or CONTRIBUTING file. Provider prerequisites will be summarized in tables while preserving the current platform-specific notes.
- 2026-09-21T10:27:39+02:00 — README refactor complete. Added a centered assets/logo.png header, product tagline, Flutter/platform badges, feature highlights, provider and dependency tables, streamlined first-run steps, and grouped provider notes. Verified the relative logo asset exists, the clone URL resolves over Git, and git diff --check -- README.md passes. No application tests were run because this is documentation-only.
