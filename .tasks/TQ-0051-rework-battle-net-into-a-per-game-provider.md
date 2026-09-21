---
id: TQ-0051
title: Rework Battle.net into a per-game provider
status: done
priority: high
labels:
  - refactor
  - component/backend
  - component/frontend
created: 2026-09-21T11:37:31+02:00
updated: 2026-09-21T11:50:52+02:00
---

# Battle.net: one provider, a list of games, no config parsing

## Why

Reading `product.db` cannot work in the sandbox. The app has no grant for
`/Users/Shared/Battle.net/Agent/product.db`, so `exists()` returns true
(metadata is readable) and `readAsBytes()` throws `PathAccessException`,
which failed the whole provider before discovery started:

    ERROR [provider] Provider "Battle.net" failed.
      PathAccessException: Cannot open file,
      path = '/Users/Shared/Battle.net/Agent/product.db'
      (OS Error: Operation not permitted, errno = 1)

Asking the user to grant that path to read a database that only lists install
locations is not worth it. Existence checks need no grant, so the games can be
inferred from their screenshot folders directly.

## Shape

One provider, a list of games. Each game is its own row in Settings with:

- an on/off toggle, under the Battle.net master switch
- a found-check on its default screenshot folder (`existsSync`, no grant
  needed — the sandbox allows metadata and denies data)
- Allow Access on macOS, per game
- Use custom folder, per game, like the other providers

Decisions taken with the user:

- World of Warcraft is three rows: Retail, Classic, Classic Era.
- Each row is its own album: `PC/World of Warcraft`, `PC/WoW Classic`,
  `PC/WoW Classic Era`.
- Games: World of Warcraft (x3), Diablo IV, Diablo III, StarCraft II,
  Overwatch 2. Only paths that could be verified go in.
- WoW Forever ships 4 November; its folder name is unknown, so it is left out
  and added later as one entry in the table.
- The provider-level "games root" override is dropped. Per-game custom folders
  replace it.

## The table

| Row | Album | macOS | Windows |
| --- | --- | --- | --- |
| World of Warcraft | `PC/World of Warcraft` | `/Applications/World of Warcraft/_retail_/Screenshots` | `…/World of Warcraft/_retail_/Screenshots` |
| WoW Classic | `PC/WoW Classic` | `…/_classic_/Screenshots` | `…/_classic_/Screenshots` |
| WoW Classic Era | `PC/WoW Classic Era` | `…/_classic_era_/Screenshots` | `…/_classic_era_/Screenshots` |
| Diablo IV | `PC/Diablo IV` | — (no macOS client) | `~/Pictures/Diablo IV`, `~/Documents/Diablo IV/Screenshots` |
| Diablo III | `PC/Diablo III` | `~/Documents/Diablo III/Screenshots` | same |
| StarCraft II | `PC/StarCraft II` | `~/Documents/StarCraft II/Screenshots` | same |
| Overwatch 2 | `PC/Overwatch 2` | `~/Documents/Overwatch/ScreenShots/Overwatch` | same |

## Scope

1. Rewrite `battle_net_games.dart` as a flat game table. Delete
   `battle_net_catalog.dart`, its test, and the protobuf reader with it.
2. `BattleNetSettings`: a master `enabled` plus per-game `ProviderSettings`,
   keyed by game id. Migrate the old single `battleNet` object — keep
   `enabled`, drop the root path. Bump the settings version.
3. Provider: iterate enabled games, resolve each folder (custom, else the
   platform default), import into that game's album.
4. `folderRequirements`: one per enabled game whose folder exists or has a
   custom path, so a game nobody owns never asks for a grant.
5. Settings: a row per game with toggle, found-check, Allow Access and a
   custom folder field. `SettingsFolderTarget` carries a game id.
6. Tests for the table, the provider, the settings migration and the rows.

## Done when

- Nothing reads `product.db`, and nothing touches `/Users/Shared`.
- With only World of Warcraft installed, exactly one grant is requested and
  one album is written.
- A game with no default folder on this platform still offers a custom folder.
- Settings written by the previous version still load.
- `make check` passes.

---

## Notes

- 2026-09-21T11:50:52+02:00 — Implemented.

  Gone: battle_net_catalog.dart and its protobuf reader, the product.db read,
  and every path under /Users/Shared. Also gone: the provider-level games-root
  override.

  battle_net_games.dart is now a flat table of 7 entries - World of Warcraft,
  WoW Classic, WoW Classic Era, Diablo IV, Diablo III, StarCraft II,
  Overwatch 2 - each with a stable id, a settings-row name, an album name and
  per-OS candidate paths. BattleNetLocator.resolve() picks a custom folder over
  the defaults and reports whether the folder is there, using existsSync: the
  sandbox allows stat and denies open, which is what makes discovery possible
  without asking for anything.

  BattleNetGameFolder.isUsable is the rule that keeps the grant prompts honest:
  a game is only asked about when its folder exists, or when the user set a
  custom one. A game nobody installed never prompts.

  Settings model: BattleNetSettings holds the master switch plus a
  ProviderSettings per game id. A game with nothing stored reads as enabled, so
  turning on Battle.net works without ticking seven boxes. Settings from before
  the split keep only the master switch - the old single path pointed at a games
  root and there is no way to attribute it to a game. Version bumped to 12.

  Settings page: a _BattleNetGameRow per game with its switch, a found-check, an
  Allow Access row on macOS and its own Use custom folder field. Keys are
  battle-net-game-<id>{,-enabled,-custom,-path,-access}. SettingsFolderTarget
  gained battleNetGameCustom/battleNetGameAutomatic and chooseFolder takes a
  gameId.

  One correctness fix found while testing: _validateAndSave reverted the whole
  battleNet object whenever the provider reported any error, which threw away a
  per-game toggle just because another game's folder was missing. It now reverts
  only the games that actually failed.

  Verified on this machine:

    FOUND     World of Warcraft  /Applications/World of Warcraft/_retail_/Screenshots
    not found WoW Classic        /Applications/World of Warcraft/_classic_/Screenshots
    not found WoW Classic Era    /Applications/World of Warcraft/_classic_era_/Screenshots
    not found Diablo IV          (no path on this platform)
    not found Diablo III         /Users/fmartingr/Documents/Diablo III/Screenshots
    not found StarCraft II       /Users/fmartingr/Documents/StarCraft II/Screenshots
    not found Overwatch 2        /Users/fmartingr/Documents/Overwatch/ScreenShots/Overwatch
    --- grants requested ---
    provider.battleNet.wow_retail -> /Applications/World of Warcraft/_retail_/Screenshots

  One game installed, one grant requested. make check passes (177 tests).

  WoW Forever ships 4 November; it is one entry in the table once its folder
  name is known.
