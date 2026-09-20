---
id: TQ-0028
title: Remove the ExifTool binary dependency
status: todo
priority: normal
labels:
  - refactor
  - component/backend
  - component/frontend
created: 2026-09-20T14:24:15+02:00
updated: 2026-09-20T17:12:35+02:00
---

# Removing the ExifTool dependency

Research date: 2026-09-20
Cross-checked against the original Go project at `~/Code/games-screenshot-manager`.

## Decision

**Delete `lib/services/exiftool_service.dart`.** No Dart EXIF library is needed to replace it.

Both remaining call sites ask ExifTool for `FileModifyDate`, which is in its **System** group — *"the filesystem modification date/time"*, a pseudo-tag, not embedded metadata. Dart returns the same value from `FileStat.modified`, and the codebase already does this in `MediaImporter.copyByModifiedDate` (`lib/services/media_importer.dart:9`), which Diablo IV, Hytale, Minecraft, and Steam use.

So the binary is spawned once per file to read a number `dart:io` hands over for free.

## Why the original project needed it, and this one does not

`exif.go:68` declares one shared requirement — *"reads the capture date from a screenshot"* — and three providers return it from `Requirements()`. They do not ask for the same thing:

| Provider | Tag read | What that tag is |
| --- | --- | --- |
| Guild Wars 2 (`guildwars2.go:23`) | `FileModifyDate` | filesystem mtime |
| PlayStation 4 (`playstation4.go:21`) | `FileModifyDate` | filesystem mtime |
| Xbox Game Bar (`xboxgamebar.go:112,141,161`) | `MicrosoftGameDVRTitle`, `MicrosoftGameDVRExtended`, `Title`, `MediaCreateDate` | real embedded metadata |

Xbox Game Bar was the only provider that genuinely needed a metadata reader, and not merely for a date: the **game name** lives inside the file, and the provider skipped any capture it could not name. **Xbox Game Bar support was dropped from this project (TQ-0008, rejected), so that need is gone.** The original README describes all three as reading "the capture date from a screenshot" — accurate for Xbox, loose for the other two.

No remaining provider reads embedded metadata. Guild Wars 2 and PlayStation 4 read an mtime; PlayStation 4's `.mp4` branch and every PlayStation 5 path parse the filename (`parsePlayStationTimestamp`).

## What still uses it

| Call site | Current | Replacement |
| --- | --- | --- |
| `lib/providers/guild_wars_2_provider.dart:131` | `dateReader.fileModifiedAt(f)` → `importer.copyAtDate(...)` | `importer.copyByModifiedDate(f, destination)` |
| `lib/providers/playstation_4_provider.dart:118` (`.jpg` branch) | same | same |
| `lib/providers/guild_wars_2_provider.dart:104` | `await dateReader.ensureAvailable()` | delete |
| `lib/providers/playstation_4_provider.dart` | `ensureAvailable()` | delete |

## Equivalence check

`copyAtDate` names the file with `formatDate()` (`lib/services/media_importer.dart:105`), then calls `setLastModified(capturedAt)`.

- **Filename:** identical. ExifTool prints whole seconds; `formatDate` formats whole seconds.
- **Timezone:** identical. ExifTool prints local wall-clock time with a local offset, and `parseExifToolDate` deliberately discards the offset and builds a local `DateTime`. `FileStat.modified` is already local.
- **Sub-second mtime:** the only difference. `setLastModified` will carry the source's sub-second precision instead of a truncated second. Nothing in the app reads below a second.

## Scope of the change

1. Delete `lib/services/exiftool_service.dart` and its two imports.
2. Guild Wars 2: drop `dateReader`, the `ensureAvailable()` call, and switch to `copyByModifiedDate`.
3. PlayStation 4: same, and **delete the surrounding `try`/`catch` + `skipped++`** in the `.jpg` branch — reading an mtime cannot fail the way a missing binary could. Skipping a screenshot because ExifTool was absent was the only reason that branch existed.
4. Settings: remove `'Requires ExifTool to read screenshot dates.'` (`lib/screens/settings_page.dart:497`) and `'Requires ExifTool.'` (`lib/screens/settings_page.dart:732`).
5. README: drop the ExifTool requirement line. FFmpeg/FFprobe stay — `video_metadata_service.dart` still shells out to `ffprobe`, and that one is a real external need.
6. Tests: drop `_FakeExifDateReader` and the `parseExifToolDate` / "ExifTool is required" cases from `test/providers/guild_wars_2_provider_test.dart` and `test/providers/playstation_4_provider_test.dart`. Keep the import assertions — dates now come from a real temp file's mtime, set with `setLastModified` in the fixture.

## Dart metadata libraries, for the record

Nothing here is needed for this change. It matters only if a future provider has to read metadata a filename cannot give:

- **`image: ^4.10.1`** (already a direct dependency) exposes `decodeJpgExif(Uint8List) → ExifData` (`image-4.10.1/lib/src/formats/formats.dart:366`), so `exif?.exifIfd['DateTimeOriginal']` gives a JPEG's true capture time. Its PNG decoder handles **`tEXt` only** (`png_decoder.dart:65`) — no `zTXt`, no `iTXt` — and it has no MP4 support.
- **`exif_reader` 4.2.0** — verified publisher (mgenware.com), 160/160 pub points. Pure Dart: it supports all 6 platforms plus Web and WASM, which rules out FFI and platform channels. Covers JPEG/HEIC/AVIF/PNG/WebP/JXL and raw formats — EXIF tags only, not MP4 boxes or arbitrary PNG text chunks.
- **`exif` 3.3.0** (bigflood) — the older, more popular original, last published ~2024, unverified uploader. `exif_reader` is its maintained successor.

Note for anyone reviving an Xbox-Game-Bar-shaped provider: **no Dart EXIF library covers that case.** Game DVR metadata lives in PNG `iTXt`/`zTXt` chunks and MP4 boxes, which is why the original project reached for ExifTool.

If a provider ever needs a true JPEG capture date, `parseExifToolDate` already parses the `YYYY:MM:DD HH:MM:SS` shape those libraries return, so it is the one piece worth preserving from the deleted file.

## Done when

- `rg -i exiftool` returns nothing outside this task file.
- Guild Wars 2 and PlayStation 4 import with correct dates on a machine with no `exiftool` on `PATH`.
- `make check` passes.

---

## Notes

- 2026-09-20T14:56:42+02:00 — Cross-checked the original Go project. ExifTool is mandatory there for three providers, but only Xbox Game Bar reads real embedded metadata (MicrosoftGameDVRTitle/Extended in PNG, Title/MediaCreateDate in MP4) — including the game name, which has no fallback. Guild Wars 2 and PlayStation 4 both ask for FileModifyDate, which is the System-group filesystem mtime. TQ-0008 has since implemented Xbox Game Bar here with a dependency-free PNG-chunk and MP4-box reader, so the remaining ExifTool uses are mtime lookups only. Rewrote the body accordingly; the earlier version claimed the project never reads embedded metadata, which was wrong.
- 2026-09-20T15:36:54+02:00 — Xbox Game Bar support was removed (TQ-0008 rejected, code gone from the tree), so the one provider that needed real embedded metadata is no longer in scope. Rewrote the body: no remaining provider reads embedded metadata, and the two surviving ExifTool call sites are FileModifyDate mtime lookups. Dropped the stale 'land after TQ-0008' ordering note and the reference to lib/services/xbox_game_bar_metadata.dart, which no longer exists. Kept the original-project tag table as the record of why the dependency existed.
- 2026-09-20T16:33:34+02:00 — Verified empirically with exiftool 13.55. Wrote a JPEG with DateTimeOriginal=2020:01:02 03:04:05, then set its mtime to 2026-06-15 09:10:30 with touch:

    exiftool -FileModifyDate -s3   -> 2026:06:15 09:10:30+02:00
    stat -f %Sm                    -> 2026:06:15 09:10:30
    Dart FileStat.modified         -> 2026-06-15 09:10:30.000
    exiftool -DateTimeOriginal -s3 -> 2020:01:02 03:04:05   (ignored by both providers)

  exiftool -G reports the tag as [File], not [EXIF]. FileModifyDate tracks the mtime and is unrelated to the embedded date.

  Also confirmed in the Go source which providers use the lib: exif.go, guildwars2.go, playstation4.go and xboxgamebar.go import barasher/go-exiftool. PlayStation 5 does not - its only Requirement is ffprobe (playstation5.go:168). PlayStation 4 initializes exiftool but reads exactly one key from the tag map, exifTags[ps4ExifTimeTag] at playstation4.go:105, where ps4ExifTimeTag is FileModifyDate (playstation4.go:21). Guild Wars 2 is the same shape at guildwars2.go:97 and :23.
- 2026-09-20T16:33:44+02:00 — Pre-existing limitation, unchanged by this task: playstation5.go:93 records that on exported console media the modification time is the time of the copy to the USB drive, not the capture time. PlayStation 4 screenshots dated from FileModifyDate inherit that, in the Go project and here. Switching to FileStat.modified preserves the behaviour exactly - it neither fixes nor worsens it. If PS4 dates ever look wrong, the fix is reading the real EXIF DateTimeOriginal, which is a separate behaviour change.
- 2026-09-20T17:12:35+02:00 — Verified against real files in ~/Syncthing/games-screenshot-gallery (read-only; nothing modified).

  FileModifyDate == mtime on 14 of 14 real files - 6 PlayStation 4, 6 Guild Wars 2, 2 raw Diablo IV. Never diverged. The core claim holds on real console and game output, not just synthetic fixtures.

  Guild Wars 2: the conclusion is exactly right. Those JPEGs carry NO EXIF block at all - exiftool -G reports only [File] tags (modify, access, inode change). mtime is the only date that exists, so no EXIF library could ever help and the swap to FileStat.modified is strictly equivalent.

  PlayStation 4: needs a caveat. Those JPEGs DO carry a real console-written DateTimeOriginal and CreateDate, and on every sampled file it matches the capture time the filename records. The gallery shows why that matters: all six PS4 samples have mtime 2024:10:14 00:05:48 - one bulk copy - while DateTimeOriginal still holds the true 2021 capture time. FileModifyDate is a strictly worse source than what is already inside the file. The Go tool never writes metadata (no WriteMetadata calls), so that DateTimeOriginal is the console's own. Filed as a follow-up.
