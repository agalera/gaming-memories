---
id: TQ-0067
title: Rename providers to sources
status: done
priority: normal
labels:
  - component/frontend
  - component/backend
created: 2026-09-22T08:37:21+02:00
updated: 2026-09-22T08:37:58+02:00
---

## Scope

"Provider" was the app's word for a place captures are collected from. The word
is "source" everywhere now: the UI, the Dart vocabulary, the settings file and
the documentation.

- UI copy: the **Sources** settings tab, "Library and source setup", "Collect
  from enabled sources", "Enable a source in Settings first." and the folder
  validation messages.
- Code: `ScreenshotProvider` -> `ScreenshotSource`, `SteamProvider` ->
  `SteamSource` and the rest of the classes, `lib/providers/` -> `lib/sources/`
  with `*_provider.dart` -> `*_source.dart`, `provider_paths.dart` ->
  `source_paths.dart`, `ProviderSettings` -> `SourceSettings`, `providerPaths`
  -> `sourcePaths`, the `provider` log category -> `source`, and the widget
  keys.
- Settings file: the `folderGrants` keys are `source.steam` and the rest. The
  app has no releases, so no saved file carries the old keys and nothing
  migrates them.
- README and the website.

Flutter's own names stay: `path_provider`, `SingleTickerProviderStateMixin`,
`ImageProvider` and the local that holds one.

---

## Notes

- 2026-09-22T08:37:58+02:00 — Renamed in one pass over lib and test, with Flutter's own names protected
  (path_provider, SingleTickerProviderStateMixin, ImageProvider). Three things
  needed a hand afterwards: a local in the PlayStation 4 test shadowed the
  Directory fixture named source, the relative import blocks fell out of
  alphabetical order once providers/ became sources/, and the ImageProvider field
  in the gallery cover kept its own name since it holds a Flutter provider, not a
  capture source.

  The folderGrants keys are source.* with no migration, as agreed: the app has no
  releases, so no settings file carries the old keys.

  make check is green: format, analyze and 194 tests. The two test files that
  failed format-check on master are formatted now, since the rename rewrote
  them.
