---
id: TQ-0052
title: Add basic GitHub Actions CI checks
status: done
priority: normal
labels:
  - component/ci
  - chore
created: 2026-09-21T11:54:08+02:00
updated: 2026-09-21T13:20:21+02:00
---

Add a minimal GitHub Actions workflow for pushes and pull requests. It should install the project's pinned Flutter channel/version, restore dependencies, and run the repository's standard checks.

## Done when

- GitHub Actions runs the checks on pushes and pull requests.
- The workflow uses the repository's existing check command.
- The workflow YAML is validated and the checks pass locally.

---

## Notes

- 2026-09-21T11:56:00+02:00 — Added .github/workflows/ci.yml for pushes and pull requests. It grants contents: read only, installs the stable Flutter channel with SDK/pub caching, restores packages, and runs make check with the local FVM wrapper disabled. Verified with Ruby YAML parsing, git diff --check, make command expansion, and make check (formatting, analyzer, and all 177 tests passed).
- 2026-09-21T13:20:21+02:00 — Follow-up: pinned actions/checkout v6 to d23441a48e516b6c34aea4fa41551a30e30af803 and subosito/flutter-action v2 to 1a449444c387b1966244ae4d4f8c696479add0b2, retaining version comments for Dependabot. Added .github/dependabot.yml with a monthly github-actions schedule and one group matching all Actions dependencies. YAML parsing, full-SHA inspection, git diff --check, and make check all pass (182 tests).
