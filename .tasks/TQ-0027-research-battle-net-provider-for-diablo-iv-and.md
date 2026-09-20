---
id: TQ-0027
title: Research Battle.net provider for Diablo IV and World of Warcraft
status: done
priority: normal
labels:
  - feature
  - component/backend
created: 2026-09-20T10:52:26+02:00
updated: 2026-09-20T10:52:37+02:00
---

Research whether the Diablo IV and World of Warcraft providers can be combined into a single "Battle.net" provider that detects the Battle.net client and auto-discovers installed games, on Windows and macOS at minimum, with a custom path fallback on Linux (no Battle.net client).

## Verdict

Feasible. `product.db` is the right hook, but it buys less than expected: the recorded install path only helps World of Warcraft. Diablo IV writes screenshots to a fixed `Documents` path unrelated to its install location, and has no macOS client at all.

Recommendation: do not merge the providers. Extract a shared discovery service instead. See "Recommendation" below.

## Detection: product.db is the source of truth

| Platform | Agent DB | Client config (JSON) |
| --- | --- | --- |
| Windows | `%ProgramData%\Battle.net\Agent\product.db` | `%APPDATA%\Battle.net\Battle.net.config` |
| macOS | `/Users/Shared/Battle.net/Agent/product.db` | `~/Library/Application Support/Battle.net/Battle.net.config` |
| Linux | none (Wine prefix only) | none |

Verified on a macOS host: `/Users/Shared/Battle.net/Agent/product.db` exists, mode `0777`, readable with no permission prompt. On Windows the file carries a hidden flag but `ProgramData` is world-readable, so no elevation is needed.

### Format

`product.db` is a protobuf blob. Canonical schema, confirmed by two independent implementations:

```proto
message ProductDb      { repeated ProductInstall product_installs = 1; }
message ProductInstall { string uid = 1; string product_code = 2;
                         UserSettings settings = 3; CachedProductState cached_product_state = 4; }
message UserSettings   { string install_path = 1; string play_region = 2; }
message CachedProductState { BaseProductState base_product_state = 1; }
message BaseProductState   { bool installed = 1; bool playable = 2; string current_version_str = 7; }
```

Only four nested fields are needed, so a hand-rolled varint / length-delimited reader is enough and no pubspec dependency is required. A ~35-line reference implementation run against the real file on the macOS host returned:

```
uid='agent'  code='agent'  installed=True  playable=True  path='/Users/Shared/Battle.net/Agent'
```

Entries whose `product_code` is `agent` or `bna` are the launcher itself and must be skipped.

Caveat: the verification host has only the Agent installed, no games, so the multi-entry case is unverified locally. The schema itself is confirmed by the sources below.

### Relevant uids

| `uid` | `product_code` | Game |
| --- | --- | --- |
| `wow`, `wow_classic`, `wow_classic_era` | `WoW` | World of Warcraft (retail / Cata / Vanilla) |
| `fenris` | `Fen` | Diablo IV |
| `diablo3` | `D3` | Diablo III |
| `osi` | `OSI` | Diablo II: Resurrected |
| `prometheus` | `Pro` | Overwatch 2 |
| `s2` | `S2` | StarCraft II |
| `heroes` | `Hero` | Heroes of the Storm |
| `hs_beta` | `WTCG` | Hearthstone |
| `w3` | `W3` | Warcraft III: Reforged |
| `rtro` | `RTRO` | Blizzard Arcade Collection |

Windows fallback, which Playnite tries first: Uninstall registry keys whose `UninstallString` matches `Battle\.net.*--uid=(.*?)\s`, reading `InstallLocation`. Unreliable, because Battle.net skips these keys for games that were imported rather than installed. Treat the registry as the fallback and `product.db` as primary.

## Install path is not the screenshot path

| Game | Screenshot folder | Derivable from `install_path`? |
| --- | --- | --- |
| World of Warcraft | `<install>/_retail_/Screenshots`, `_classic_/`, `_classic_era_/` | Yes. This is the real win. |
| Diablo IV | `%USERPROFILE%\Documents\Diablo IV\Screenshots` | No. Fixed per-user path. |
| Overwatch 2 | `Documents\Overwatch\ScreenShots\Overwatch\` | No |
| Diablo III, StarCraft II, Heroes of the Storm | `Documents\<Game>\Screenshots\` | No |

Default install roots: `C:\Program Files (x86)\World of Warcraft` on Windows, `/Applications/World of Warcraft` on macOS. Both use the same `_retail_` / `_classic_` / `_classic_era_` flavor layout.

For Diablo IV, `product.db` yields exactly one useful fact: a reliable installed/not-installed gate. That would replace the current blind directory probe that produces a skipped-provider warning, but it does not justify a merged provider on its own.

## Blockers

1. Diablo IV is Windows-only. There is no native macOS client and no announced plans for one. A Battle.net provider on macOS will never surface Diablo IV, only World of Warcraft and the other Blizzard titles.

2. The World of Warcraft provider does not exist yet. TQ-0007 is still `todo`, so this would merge one shipped provider into one unwritten one.

3. macOS sandbox. `macos/Runner/Release.entitlements` grants only `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-write`. Neither `/Users/Shared/Battle.net/Agent/` nor `/Applications/World of Warcraft/` is user-selected, so auto-discovery on macOS is blocked until TQ-0026 (security-scoped bookmarks) lands. The existing providers sidestep this by gating auto-discovery behind `Platform.isWindows`, which a Battle.net provider would also have to do, defeating the point on the one desktop OS where World of Warcraft actually runs. TQ-0026 is a hard prerequisite for macOS auto-discovery.

## Architecture fit

- Fan-out is already solved. `SteamProvider` returns a single `ImportResult` while writing into many `PC/<gameName>` album folders. A Battle.net provider copies that shape directly.
- Album names stay per-game (`PC/World of Warcraft`, `PC/Diablo IV`), never `PC/Battle.net`. Otherwise existing Diablo IV libraries need a TQ-0015-style album migration.
- Collapsing the `diabloIV` settings key into a `battleNet` key bumps `AppSettings.toJson` past version 5. `ProviderSettings.fromJson` already carries legacy-path handling to model the migration on.
- World of Warcraft needs `.tga` support. The `screenshotFormat` CVar accepts `jpg` (default), `png` and `tga`, and the filename pattern is `WoWScrnShot_MMDDYY_HHMMSS.<ext>`. Flutter's `Image` cannot decode TGA, so this reaches `thumbnail_service` and the gallery, not just the importer.

## Recommendation

Do not merge the providers. Extract a shared discovery service instead.

Add `lib/services/battle_net_catalog.dart`, returning `Map<String uid, BattleNetInstall>` parsed from `product.db`, with the Windows uninstall-registry fallback.

- `DiabloIVProvider` asks it whether `fenris` is installed, replacing the current blind directory probe with a real answer. Its screenshot path stays the hardcoded Documents/Pictures pair.
- A new `WorldOfWarcraftProvider` (TQ-0007) asks it where `wow` lives, then enumerates `_retail_`, `_classic_` and `_classic_era_` under that root. This is where `product.db` genuinely pays off.
- Both keep their own toggle, their own album, and their own custom-path escape hatch for Linux and Wine.

Flip to a single merged `BattleNetProvider` only if the other eight Blizzard titles are in scope. At that point one toggle beats nine, and the shared `Documents\<Game>\Screenshots` pattern for Overwatch 2, Diablo III, StarCraft II and Heroes of the Storm makes the merge carry its weight.

## Sources

- galaxy-integration-battlenet, `src/consts.py`, `src/product_db.proto`, `src/parsers.py`: https://github.com/FriendsOfGalaxy/galaxy-integration-battlenet
- Playnite `BattleNetLibrary.cs` and `BattleNetGames.cs`: https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/BattleNetLibrary/BattleNetGames.cs
- Playnite issue #93, change detection of installed Battle.net games: https://github.com/JosefNemec/PlayniteExtensions/issues/93
- wowdev.wiki TACT Products, TACT product to Agent UID mapping: https://wowdev.wiki/TACT
- blizzard-product-parser: https://github.com/TinkoLiu/blizzard-product-parser
- PCGamingWiki Store:Battle.net: https://www.pcgamingwiki.com/wiki/Store:Battle.net
- PCGamingWiki World of Warcraft: https://www.pcgamingwiki.com/wiki/World_of_Warcraft
- PCGamingWiki Diablo IV: https://www.pcgamingwiki.com/wiki/Diablo_IV
- Warcraft Wiki, changing the screenshot format: https://warcraft.wiki.gg/wiki/Screenshot
- Diablo IV forums, screenshot folder location: https://us.forums.blizzard.com/en/d4/t/anybody-know-location-of-screenshots-folder/2167
- Blizzard Support, Deleting Battle.net Files: https://us.battle.net/support/en/article/34719

---

## Notes

- 2026-09-20T10:52:33+02:00 — Research complete, read-only, no source files touched.

  Method: read lib/providers/*, lib/models/app_settings.dart and macos/Runner/*.entitlements for architecture fit; inspected a real /Users/Shared/Battle.net/Agent/product.db on the macOS host and confirmed the ProductInstall field layout by hexdump; cross-checked the protobuf schema and the Windows/macOS agent paths against galaxy-integration-battlenet and Playnite's BattleNetLibrary; validated a dependency-free ~35-line varint parser against that file.

  Outcome: merging Diablo IV and World of Warcraft into one Battle.net provider is not recommended. Extract a shared battle_net_catalog service instead, keeping both providers and both albums separate. Implementation is deliberately not filed here: it belongs on TQ-0007 (World of Warcraft provider) once TQ-0026 unblocks macOS auto-discovery.
