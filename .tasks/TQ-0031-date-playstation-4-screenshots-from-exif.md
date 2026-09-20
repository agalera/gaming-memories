---
id: TQ-0031
title: Date PlayStation 4 screenshots from EXIF DateTimeOriginal
status: todo
priority: normal
labels:
  - component/backend
  - bug
depends_on:
  - TQ-0028
created: 2026-09-20T17:12:55+02:00
updated: 2026-09-20T17:19:20+02:00
---

# PlayStation 4 should read the console's capture date, not the file's mtime

Research date: 2026-09-20
Evidence: real files in `~/Syncthing/games-screenshot-gallery` (inspected read-only).

## The problem

`lib/providers/playstation_4_provider.dart` dates `.jpg` captures from the file's modification time. That time is not the capture time — it is whenever the file was last written, which for console media means the copy to the USB drive, and after that any sync or copy that does not preserve timestamps.

`playstation5.go:93` in the original project already recorded this:

> *"A PS5 JPEG carries no EXIF date, and the modification time is the time of the copy to the USB drive."*

True for PS5. **Not true for PS4** — and that is the opportunity.

## PS4 JPEGs carry a real capture date

Every PlayStation 4 screenshot sampled in the gallery has a console-written `DateTimeOriginal` and `CreateDate`, and each one matches the capture time exactly:

```
Genshin Impact/2021-09-07_18-31-12.jpg
  DateTimeOriginal : 2021:09:07 18:31:12   <- the real capture
  FileModifyDate   : 2024:10:14 00:05:48   <- a bulk copy, 3 years later
```

All six PS4 samples share that same `2024:10:14 00:05:48` mtime — one copy operation flattened every one of them — while `DateTimeOriginal` survived intact. The filenames are right only because the import happened while the source mtimes were still good.

The original Go tool never wrote metadata (no `WriteMetadata` calls anywhere), so that `DateTimeOriginal` is the console's own, not something the pipeline added.

Guild Wars 2 is the opposite case and needs no change: those JPEGs carry **no EXIF block at all** — `exiftool -G` reports only `[File]` tags — so mtime is the only date that exists.

## The change

Read `DateTimeOriginal` from the JPEG and fall back to the mtime when it is absent.

No new dependency. **`image: ^4.10.1` is already a direct dependency** and decodes EXIF without touching the pixels:

```dart
// image-4.10.1/lib/src/formats/formats.dart:366
final exif = decodeJpgExif(await file.readAsBytes());
final raw = exif?.exifIfd['DateTimeOriginal']?.toString(); // '2021:09:07 18:31:12'
```

The value comes back in the `YYYY:MM:DD HH:MM:SS` shape, with no zone. Treat it as local wall-clock time, the way the console wrote it.

Keep this behind the provider's existing injectable seam so tests can supply a fake reader, the way `dateReader` worked before TQ-0028 removed it.

## Watch out for

- **This renames files.** `copyAtDate` derives the destination name from the date, so captures imported under an mtime-derived name will not match a later EXIF-derived name, and the importer will write a second copy rather than recognise the duplicate. Decide whether that is acceptable or whether existing libraries need a migration, the way TQ-0015 handled the Steam album rename.
- `decodeJpgExif` takes the whole file as bytes. Fine for screenshots; do not extend the same approach to clips.
- PS4 `.mp4` clips keep their filename-derived dates. Nothing here touches them.
- PlayStation 5 is unaffected — its JPEGs carry no EXIF date, so the filename stays the only source.

## Done when

- A PS4 screenshot with a clobbered mtime still imports under its true capture date.
- A PS4 screenshot with no EXIF date still imports, dated from its mtime.
- Guild Wars 2 is untouched.
- `make check` passes.

---

## Notes

- 2026-09-20T17:19:20+02:00 — Verified that the Dart path needs no exiftool binary. Built a throwaway package depending only on image ^4.10.1 and ran it with PATH stripped to /usr/bin:/bin, against real files in ~/Syncthing/games-screenshot-gallery:

    exiftool on PATH? false
    2021-09-07_18-31-12.jpg (PS4)  DateTimeOriginal = 2021:09:07 18:31:12
                                   Make = Sony Interactive Entertainment Inc.
                                   mtime = 2024-10-14 00:05:48.413903
    2019-08-13_18-45-32.jpg (GW2)  DateTimeOriginal = (none)

  decodeJpgExif parses the JPEG bytes in-process. The confusion is worth recording: the Go project's barasher/go-exiftool is a wrapper that shells out to the exiftool binary, whereas image, exif_reader and exif are Dart decoders that need nothing installed. The Make tag also confirms the console writes that EXIF itself.
