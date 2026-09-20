---
id: TQ-0042
title: Validate all Steam settings and authentication
status: done
priority: high
labels:
  - backend
created: 2026-09-20T20:13:05+02:00
updated: 2026-09-20T20:30:48+02:00
---

Validate only the Steam fields that the active options require. An enabled Steam provider requires a valid folder and API key authentication. Online gallery import also requires a valid SteamID64 and account authentication. Disable Steam when validation fails. Show the exact cause in the provider card and a manual-close error toast.

---

## Notes

- 2026-09-20T20:15:08+02:00 — Steam validation now always requires a 32-character Web API key and verifies it with Steam. Online gallery mode also requires a 17-digit SteamID64 and verifies that the account exists through GetPlayerSummaries. Local import validates the API key through GetAppList. Successful checks remain cached for the active credential pair. Added field, authentication, and API-call tests. Full make check passes with 132 tests and three environment skips.
- 2026-09-20T20:18:06+02:00 — User correction: Steam user ID is required whenever Steam is enabled, not only for online gallery imports. A failed save must show the exact validation error, disable Steam, and keep that error visible in the provider card.
- 2026-09-20T20:30:32+02:00 — Corrected validation scope after user clarification. Steam always requires a valid API key. SteamID64 is required and authenticated only when online gallery import is active. Invalid fields for any active provider now disable that provider, preserve its last valid folder, show the exact error in its card, and create a manual-close error toast.
