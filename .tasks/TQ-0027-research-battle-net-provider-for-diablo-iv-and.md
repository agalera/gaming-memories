---
id: TQ-0027
title: Research Battle.net provider for Diablo IV and World of Warcraft
status: done
priority: normal
labels:
  - feature
  - component/backend
created: 2026-09-20T10:52:26+02:00
updated: 2026-09-20T10:54:36+02:00
---

Research whether the Diablo IV and World of Warcraft providers can be combined into a single "Battle.net" provider that detects the Battle.net client and auto-discovers installed games, on Windows and macOS at minimum, with a custom path fallback on Linux (no Battle.net client).

Scope: the merged provider fans screenshots into the existing per-game `PC/<gameName>` albums, exactly as `SteamProvider` already does. It does not introduce a `PC/Battle.net` album.

## Verdict

Merge them. One `BattleNetProvider` shaped like `SteamProvider`: one toggle, one `ImportResult`, many `PC/<gameName>` albums. `product.db` gives a reliable list of installed products, and each uid maps to a screenshot folder that is either install-relative (World of Warcraft) or a fixed per-user `Documents` path (everything else).

The detection work is the same whether it lives in one provider or two, and the per-game screenshot map is the same table either way. Merging collapses two settings blocks into one and absorbs TQ-0007 instead of duplicating it, and every further Blizzard title is then a row in a table rather than a new provider.

## Detection: product.db is the source of truth

| Platform | Agent DB | Client config (JSON) |
| --- | --- | --- |
| Windows | `%ProgramData%\Battle.net\Agent\product.db` | `%APPDATA%\Battle.net\Battle.net.config` |
| macOS | `/Users/Shared/Battle.net/Agent/product.db` | `~/Library/Application Support/Battle.net/Battle.net.config` |
| Linux | none natively; under Wine at `<prefix>/drive_c/ProgramData/Battle.net/Agent/product.db` | same, under the prefix |

Verified on a macOS host: `/Users/Shared/Battle.net/Agent/product.db` exists, mode `0777`, readable with no permission prompt. On Windows the file carries a hidden flag but `ProgramData` is world-readable, so no elevation is needed.

Presence of a parseable `product.db` is itself the "is Battle.net installed" signal, so no separate client probe is needed.

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

## Screenshot folder per uid

The install path recorded in `product.db` resolves screenshots for World of Warcraft only. Every other title writes to a fixed per-user path, so the provider needs a uid to folder table, not just the install path.

| Game | Screenshot folder | Derivable from `install_path`? |
| --- | --- | --- |
| World of Warcraft | `<install>/_retail_/Screenshots`, `_classic_/`, `_classic_era_/` | Yes |
| Diablo IV | `%USERPROFILE%\Documents\Diablo IV\Screenshots`, plus `%USERPROFILE%\Pictures\Diablo IV` as the current provider already scans | No. Fixed per-user path. |
| Overwatch 2 | `Documents\Overwatch\ScreenShots\Overwatch\` | No |
| Diablo III, StarCraft II, Heroes of the Storm | `Documents\<Game>\Screenshots\` | No |

Default install roots: `C:\Program Files (x86)\World of Warcraft` on Windows, `/Applications/World of Warcraft` on macOS. Both use the same `_retail_` / `_classic_` / `_classic_era_` flavor layout.

For the fixed-path titles, `product.db` still earns its keep: it turns the current blind directory probe into a real installed/not-installed answer, so a missing folder for an installed game is a genuine "no screenshots yet" rather than a skipped-provider warning.

## Blockers and constraints

1. Diablo IV is Windows-only. There is no native macOS client and no announced plans for one. On macOS the provider will surface World of Warcraft and the other Blizzard titles, never Diablo IV. This is a fact about the catalogue, not an obstacle to the merge.

2. macOS sandbox. `macos/Runner/Release.entitlements` grants only `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-write`. Neither `/Users/Shared/Battle.net/Agent/` nor `/Applications/World of Warcraft/` is user-selected, so auto-discovery on macOS stays blocked until TQ-0026 (security-scoped bookmarks) lands. Until then the macOS path is the same `Platform.isWindows` gate the existing providers use, with the custom path as the escape hatch. TQ-0026 is a hard prerequisite for macOS auto-discovery.

3. World of Warcraft needs `.tga` support. The `screenshotFormat` CVar accepts `jpg` (default), `png` and `tga`, and the filename pattern is `WoWScrnShot_MMDDYY_HHMMSS.<ext>`. Flutter's `Image` cannot decode TGA, so this reaches `thumbnail_service` and the gallery, not just the importer. Either skip `.tga` at import or decode it on the way in.

## Architecture fit

- Destination is unchanged. `SteamProvider._destination` already joins `outputPath`, `PC` and `gameName`, and the Diablo IV and Guild Wars 2 providers join `outputPath`, `platform` ("PC") and `gameName`. A Battle.net provider writes to `PC/<gameName>` with no new album concept and no migration for existing `PC/Diablo IV` libraries.
- Fan-out is already solved. `SteamProvider` returns a single `ImportResult` while importing into many albums and reports aggregate progress through `ProviderProgress`. Copy that shape.
- Settings: replace the `diabloIV` key with `battleNet` as a `ProviderSettings` (enabled / useCustomPath / sourcePath). `AppSettings.toJson` moves past version 5, and `ProviderSettings.fromJson` already carries legacy-path handling to model the migration on. Consider an `ignoredGames` list mirroring `SteamSettings`, so one toggle does not force every detected Blizzard title into the library.
- Custom path on Linux and Wine: point it at the Wine prefix root and the same code works. Parse `<prefix>/drive_c/ProgramData/Battle.net/Agent/product.db`, then translate the `C:\...` install paths and the `Documents` screenshot paths to `<prefix>/drive_c/users/<user>/...`. That keeps one code path instead of a separate manual-folder mode.
- TQ-0007 is absorbed. World of Warcraft ships as part of this provider rather than as a separate one.

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
- 2026-09-20T10:54:36+02:00 — Scope correction from the requester: the Battle.net provider imports into the existing per-game PC/<gameName> albums, the same way SteamProvider does, and never creates a PC/Battle.net album.

  The first draft of this body argued against merging partly on an album-migration risk that does not exist, since PC/Diablo IV stays exactly where it is. With that removed, the recommendation flips: build one BattleNetProvider shaped like SteamProvider (one toggle, one ImportResult, many PC/<gameName> destinations) rather than a shared catalog service behind two providers. TQ-0007 is absorbed into it instead of being implemented separately.

  Unchanged by the correction: product.db remains the detection source, the uid to screenshot-folder table is still needed because only World of Warcraft is install-relative, Diablo IV is still Windows-only, TGA still needs handling, and TQ-0026 is still a hard prerequisite for macOS auto-discovery.
