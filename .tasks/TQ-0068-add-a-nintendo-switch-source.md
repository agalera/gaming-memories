---
id: TQ-0068
title: Add a Nintendo Switch source
status: done
priority: normal
labels:
  - feature
  - component/backend
  - component/frontend
created: 2026-09-22T08:50:39+02:00
updated: 2026-09-22T08:59:04+02:00
---

# Nintendo Switch (first generation) as its own source

The console shares its album exactly the way the Switch 2 does: **Album >
Copy to a Computer**, over USB, as an MTP device. So this source reuses the
Switch 2 workflow — a copied album folder on any platform, or direct USB
collection on Linux — and differs only in the USB product ID and the album
name.

## What the console reports

libmtp's own device table carries both consoles:

    { "Nintendo", 0x057e, "Switch / Switch Lite", 0x201d, DEVICE_FLAG_NONE },
    { "Nintendo", 0x057e, "Switch 2",             0x2061, DEVICE_FLAG_NONE },

So the vendor ID is shared and `057e:201d` is what says a first-generation
Switch or a Switch Lite is sharing its album.

## The captures are shaped the same

Every Switch capture in the real gallery
(`~/Syncthing/games-screenshot-gallery/Gallery/Nintendo Switch`, read-only)
uses the same names as the Switch 2:

    6323  NNNNNNNNNNNNNNNN_s.jpg
     580  NNNNNNNNNNNNNNNN_s.mp4

Not one file carries the SD card's `-<32 hex>` form, so the album-sharing mode
renames captures the same way on both consoles and the `_s` filter needs no
change.

## Shape of the work

The two sources are the same source with two product IDs, so the Switch 2
implementation moves to a shared base rather than being copied:

- `lib/sources/nintendo_switch_album.dart` holds the planning, filtering,
  staging, transfer, import and warning behaviour, plus the capture
  predicate.
- `NintendoSwitchSource` and `NintendoSwitch2Source` supply the album product
  ID, the platform name, the settings they read and the folder grant.
- `NintendoSwitch2Settings` becomes `NintendoSwitchSettings`, held twice in
  `AppSettings` under `nintendoSwitch` and `nintendoSwitch2`.
- The settings card is extracted the way `_PlayStationSourceCard` already is,
  so both consoles render from one widget.

## Known limitation

The libmtp examples take no device selector, so with both consoles sharing
their albums at once the tools answer for whichever device libmtp opens first.
Collect from one console at a time.

## Done when

- A copied Switch album folder imports into a `Nintendo Switch` library album.
- A connected console collects over USB on Linux and warns elsewhere.
- Ignored album folders, already-imported captures and `_c` copies are skipped.
- `make check` passes.

---

## Notes

- 2026-09-22T08:59:04+02:00 — Implemented. The Switch 2 collection moved to a shared NintendoSwitchAlbumSource
  base, and both consoles now subclass it with their own product ID, platform
  name, settings and folder grant. NintendoSwitch2Settings became
  NintendoSwitchSettings, held twice in AppSettings; the settings file version is
  13 and a file with no "nintendoSwitch" section loads the source disabled with
  the default ignored folders.

  The USB product ID is not a guess: libmtp's own src/music-players.h carries
  { "Nintendo", 0x057e, "Switch / Switch Lite", 0x201d } next to the Switch 2's
  0x2061, so 057e:201d is what the first-generation console and the Lite report
  while sharing the album. Both IDs now have a test that pins them.

  The settings card was extracted into _NintendoSwitchSourceCard and keyed by a
  prefix, the way _PlayStationSourceCard already worked, so the two consoles
  render from one widget instead of 130 duplicated lines.

  Verified against real hardware output rather than fixtures alone: a copied
  album built from ~/Syncthing/games-screenshot-gallery/Gallery/Nintendo Switch
  (read-only) imported 6 of 19 files - the _s JPGs and the _s MP4 - and left the
  .thumb.jpg sidecars, cover.jpg, index.html, the .metadata.json and the ignored
  "Otra carpeta" folder alone. Every real Switch capture in that gallery uses the
  same NNNNNNNNNNNNNNNN_s.jpg / _s.mp4 shape as the Switch 2, so the capture
  filter needed no change.

  make check passes: format, analyze and 205 tests. The macOS debug app builds.
