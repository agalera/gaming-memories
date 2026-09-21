---
id: TQ-0048
title: Make the Battle.net provider discover installed games automatically
status: done
priority: high
labels:
  - bug
  - component/backend
  - component/frontend
created: 2026-09-21T09:13:51+02:00
updated: 2026-09-21T09:43:58+02:00
---

# Battle.net provider: discover games instead of asking for one folder

## The problem

The provider is billed as "PC · Diablo IV and World of Warcraft", but in
practice it imports **one** game per run — whichever folder the user pointed
at. Merging the two providers into one did not deliver the behaviour it was
merged for.

## What it does now

1. `BattleNetProvider` implements `FolderBackedScreenshotProvider`, which
   exposes exactly one `folderGrantId` and one `folderRequirement`. One
   provider, one folder.
2. In automatic mode `folderRequirement` returns
   `providerPaths.battleNetRootCandidates().first`, which is
   `/Applications/World of Warcraft` on macOS and
   `C:\Program Files (x86)\World of Warcraft` on Windows. That is a **World of
   Warcraft install path**, not the Battle.net root, so "automatic" can only
   ever mean WoW.
3. `LibraryController._collectProvider` calls
   `provider.withFolderPath(settings, lease.grant.path)` on every grant
   activation, and `BattleNetProvider.withFolderPath` sets
   `useCustomPath: true`. On macOS the provider is therefore **always** forced
   into custom-path mode, so `collect` runs `_sourcesFromRoot(grantedFolder)`
   and never `_automaticSources()`. This is the "it's either one or the other"
   the report describes.
4. `ProductDatabaseBattleNetCatalog` does parse `product.db`, but only two uids
   are mapped: the WoW family (`wow`, `wow_classic`, `wow_classic_era`) and
   `fenris` (Diablo IV). Every other Blizzard product is dropped.
5. For `fenris` the code falls back to `providerPaths.diabloIVScreenshots()`,
   which returns `[]` on any non-Windows platform, so Diablo IV resolves to
   nothing on macOS regardless.
6. The settings copy points the user at a single game: field label
   "Battle.net or game installation folder", hint `/path/to/World of Warcraft`.

### Verified on this machine (macOS)

- `/Users/Shared/Battle.net/Agent/product.db` exists but is 342 bytes and
  lists only `agent` — **no games at all**.
- `/Applications/World of Warcraft/_retail_/Screenshots` holds 524 real
  screenshots.

So a product.db-only strategy finds nothing here. `product.db` goes stale when
the Agent is reinstalled, and it never describes where a game writes its
screenshots — only where it is installed.

## Target behaviour

1. Find the Battle.net installation itself (the Agent directory / `product.db`),
   not one game's screenshots folder.
2. Read it to learn which products are installed, and where.
3. **Union** that with probing the per-OS default install and screenshot paths,
   because `product.db` is not reliable on its own.
4. Resolve each discovered product to its screenshot folder(s).
5. Import **every** discovered game in a single run, each into
   `PC/<Game Name>`, and report them together.
6. A custom path stays an override for *where to search* — a Battle.net or
   games root — never a single game's screenshots folder.

## The structural blocker

macOS is sandboxed (`com.apple.security.app-sandbox`), so every folder read
needs a security-scoped bookmark. Battle.net games do not share one root:
WoW lives under `/Applications`, the `~/Documents`-based games do not. Steam
gets away with a single grant only because every Steam game sits under one
`userdata` directory.

`AppSettings.folderGrants` is already a `Map<String, FolderGrant>`, so several
grants can be stored today. What blocks it is the interface:
`FolderBackedScreenshotProvider` exposes a single `folderGrantId` and a single
`folderRequirement`, and the controller and settings page both assume one.

Extend the interface to expose a list of requirements, with the existing
single-requirement behaviour kept as the default so the other providers do not
change. The settings card then renders one access row per required folder.

## Done when

- With Battle.net installed and several games present, one run imports all of
  them, each into its own `PC/<Game Name>` folder.
- Discovery works when `product.db` is stale or lists only `agent` — the
  default-path probe still finds the installed games.
- Automatic mode on macOS no longer collapses into custom-path mode.
- The custom path is documented and labelled as a games/Battle.net root.
- Settings copy no longer implies exactly two supported games.
- `make check` passes.

---

## Notes

- 2026-09-21T09:24:57+02:00 — Implemented.

  Shape of the fix:
  - New lib/services/battle_net_games.dart holds the product knowledge: a
    BattleNetGame list (name, product.db uids, install-relative and
    home-relative screenshot paths, extensions, capture-date strategy) plus a
    BattleNetLocator that resolves grant roots and discovers screenshot folders.
    Discovery unions product.db with default-path probing, so a stale database
    or a wrong uid costs nothing as long as the game sits in its default place.
  - FolderBackedScreenshotProvider gained folderRequirements(settings). The
    seven single-folder providers pick it up through a SingleFolderRequirement
    mixin, so only Battle.net behaves differently.
  - LibraryController handles a list at all four sites: grant restore,
    configuration validation, the authorization refresh, and _collectProvider,
    which now activates every granted folder before collecting and releases them
    all afterwards. One granted folder is enough to run.
  - BattleNetProvider.withFolderPath is a no-op in automatic mode. That was the
    bug the report described: the controller called it on every grant
    activation, which set useCustomPath, which pinned the provider to the single
    granted folder.
  - AutomaticFolderCandidate carries a grantId, and Battle.net's candidates come
    from the provider's own requirements rather than
    providerPaths.battleNetRootCandidates(). The settings card renders one access
    row per required folder.
  - Removed ProviderPaths.battleNetRootCandidates and
    ProviderPaths.diabloIVScreenshots; the locator owns that knowledge now.

  Verified on this machine: product.db lists nothing but the agent, and
  discovery still finds /Applications/World of Warcraft/_retail_/Screenshots
  with 523 importable files. make check passes (151 tests).

  Not verified, and worth a second pass by someone with the games installed: the
  product.db uids and screenshot folder names for Diablo II: Resurrected,
  StarCraft: Remastered, Warcraft III: Reforged, Hearthstone and Heroes of the
  Storm. World of Warcraft, Diablo IV, Diablo III, StarCraft II and Overwatch 2
  are the ones I am confident about. A wrong entry degrades to "game not found"
  rather than to a wrong import, and the list is one const table to correct.
- 2026-09-21T09:43:58+02:00 — Two defects reported against the first pass, both real, both fixed.

  1. The settings row claimed every Battle.net game keeps screenshots in the
     World of Warcraft installation folder. It does not: World of Warcraft is
     the only game that writes into its own install directory, and the rest
     write under Documents (and Pictures for Diablo IV on Windows). One sentence
     cannot describe folders that differ in kind, so the copy is now built per
     folder from the games that folder actually holds:

       World of Warcraft keeps its screenshots in its installation folder,
       "/Applications/World of Warcraft".
       8 Battle.net games keep their screenshots in "/Users/<user>/Documents",
       including Diablo III, Diablo II: Resurrected, StarCraft II and others.

     BattleNetLocator.grantRoots() became grantFolders(), returning a
     BattleNetGrantFolder that carries the covered game names and renders its
     own description. ProviderFolderRequirement and AutomaticFolderCandidate
     gained an optional description so it reaches the settings row.

  2. Discovery pointed inside the app's sandbox container. Inside the macOS
     sandbox $HOME is ~/Library/Containers/<bundle>/Data, so any path built from
     homeDirectory() lands in the container rather than the user's real home.
     main.dart already works around this for ProviderPathResolver, by passing
     platformUserHomeDirectory() and allowEnvironmentHome: !Platform.isMacOS;
     the provider was constructed as const BattleNetProvider() and so used the
     default locator, which read $HOME. main.dart now hands the locator the same
     real home. Covered by a test asserting that without a home handed in, the
     locator claims no Documents or Pictures folder at all rather than guessing.

  Verified on this machine: grant folders are /Applications/World of Warcraft
  (1 game) and /Users/fmartingr/Documents (8 games) - no container path - and
  discovery still finds the 523 World of Warcraft screenshots with an empty
  product.db. make check passes (153 tests).
