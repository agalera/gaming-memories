---
id: TQ-0062
title: Research the remaining binary dependencies
status: todo
priority: normal
labels:
  - refactor
  - component/backend
  - component/build
created: 2026-09-21T21:54:19+02:00
updated: 2026-09-21T21:54:27+02:00
---

# The remaining binary dependencies

Research date: 2026-09-21. Follows TQ-0028, which removed ExifTool.

This task decides one thing per binary: replace it with Dart, or declare it
properly in the packages. The two answers are not equal in value. A replaced
binary cannot be missing, cannot be the wrong version and cannot change its
output format. A declared binary can still be absent on Arch, on macOS and on
Windows, because only deb and rpm can declare anything.

## Every binary the app starts

There are exactly four call sites. `rg "Process\.(run|start)" lib/` finds all
of them.

| Call site | Binary | Purpose |
| --- | --- | --- |
| `lib/services/thumbnail_service.dart:49` | `ffmpeg` | one video frame, to a temp JPEG |
| `lib/services/video_metadata_service.dart:27` | `ffprobe` | `format=duration` |
| `lib/services/mtp_client.dart:105` | `mtp-folders`, `mtp-files`, `mtp-connect` | Nintendo Switch 2 over USB |
| `lib/services/screenshot_action_service.dart:41` | `xdg-open` / `open` / `explorer.exe` | show a capture in the file manager |

Nothing else shells out. `imclipboard` uses the GTK clipboard directly
(`imclipboard_plugin.cc:26`). `file_picker_linux` 2.0.0 uses GTK3 and the XDG
desktop portal over D-Bus, not `zenity` or `kdialog`. The `image` package is
pure Dart.

## The finding that decides two of the four

**libmpv is already a hard dependency on every platform, and libmpv contains
FFmpeg.**

- Linux: the packages declare it. `libmpv2` on deb, `mpv-libs` on rpm, `mpv` on
  Arch (`packaging/linux/nfpm.yaml`).
- Windows: `media_kit_libs_windows_video` downloads `libmpv-2.dll` at build
  time and copies it into the bundle (`windows/CMakeLists.txt:169`).
- macOS: `media_kit_libs_macos_video` vendors an `.xcframework`.

So the app already loads FFmpeg's decoders in process. It then starts a second
copy of FFmpeg as a child process to decode one frame. `docs/releasing.md:219`
already records the license audit of that bundled libmpv, so the licensing
question is answered.

The libmpv C API is reachable today with no new package:
`package:media_kit/generated/libmpv/bindings.dart` is a public import path and
holds the whole API, `mpv_create`, `mpv_set_option_string`, `mpv_command_ret`
and `mpv_wait_event` included.

## ffmpeg — replace with libmpv

**Measured.** `mpv --vo=image --vo-image-format=jpg --vo-image-outdir=DIR
--start=3 --frames=1 --no-audio FILE` wrote a 1934x1080 JPEG in 0.121 s. The
`ffmpeg` command the app runs today took 0.102 s on the same file. The two cost
the same.

**The constraint that shapes the work.** `media_kit` sets `vid=no` before
`mpv_initialize` unless a `VideoController` attaches
(`native/player/real.dart:2325`), and `PlayerConfiguration.vo` defaults to
`'null'` (`platform_player.dart:519`). A `vo=null` mpv writes no screenshot;
this was tried and produced no file. So `Player.screenshot()` on a headless
`Player` returns nothing, and the answer is not to call `Player.screenshot()`.

**The shape to build.** A small frame grabber in the scan isolate that opens
libmpv through the generated bindings, sets `vo=image`, `vid=auto` and a
per-call `vo-image-outdir`, plays one frame, then hands the file to the
existing `_generateThumbnail`. `media_kit` does the same thing for its own
screenshot: it runs the FFI call under `compute` against `NativeLibrary.path`
(`native/player/real.dart:1188`).

**Verify first.** `mpv --vo=help` lists `image` on this machine's libmpv 0.41.0.
Check the same for the `libmpv-2.dll` the Windows build downloads and for the
macOS `.xcframework`. A build without the `image` VO needs `vo=gpu` offscreen
plus `screenshot-raw` instead.

**Note.** One `vo-image-outdir` per call, because `vo=image` writes numbered
files. The scanner runs over hundreds of files.

## ffprobe — replace with an in-house header parser

**Measured on the whole real gallery.** A header parser was prototyped and run
against `~/Syncthing/games-screenshot-gallery`, then compared to `ffprobe`
file by file:

    total files          : 939   (744 mp4, 195 webm)
    header parse failed  : 0
    compared             : 939
    max difference       : 0.0672 s
    99th percentile      : 0.0669 s
    median difference    : 0.000333 s
    differences over 1s  : 0

Every file parsed. The largest gap was 67 ms, and it is the gap between the
container's own movie duration and the stream duration, not an error.

**Why 67 ms does not matter.** One caller uses the value for a date:
`playstation_5_provider.dart:130` subtracts the duration from the filename
timestamp to get a clip's start time. `formatDate` writes whole seconds. The
other caller shows a duration in the gallery. Neither reads below a second.

**What to parse.** `library_scanner.dart:21` accepts `.mp4`, `.avi`, `.mkv` and
`.webm`.

| Container | Where the duration is | Size of the job |
| --- | --- | --- |
| MP4 | `moov` > `mvhd`: duration and timescale | small, version 0 and version 1 |
| Matroska, WebM | Segment > Info: `Duration` float, `TimestampScale` | medium, needs an EBML variable-length integer reader |
| AVI | `hdrl` > `avih`: microseconds per frame, total frames | small |

The gallery holds no `.avi` and no `.mkv`, so those two are untested by the
measurement above. Write them, and test them against fixtures.

**The alternative.** The same libmpv handle built for thumbnails answers
`duration` as a property. It is one mechanism instead of two, but it makes a
cheap header read wait on a decoder. Decide this together with the ffmpeg work,
not separately.

**Rejected packages.** `media_metadata` 2.2.2 needs TagLib on Linux and still
shells out to `ffmpeg` for video, so it trades one binary for a library plus the
same binary. `metadata_audio` 0.9.3 is pure Dart and covers MP4 and Matroska,
but it is an audio parser at version 0.9 with 2 likes, and it does not document
a video duration. Neither is better than the parser measured above.

## The libmtp tools — replace with an FFI binding, and fix the packages

Two separate problems. Both need fixing.

### The packaging is wrong on rpm today

`packaging/linux/nfpm.yaml` suggests `libmtp` on rpm. On Fedora `libmtp` is the
shared library. The `mtp-files`, `mtp-folders` and `mtp-connect` commands are in
**`libmtp-examples`**. So a Fedora user who accepts the suggestion still has no
tools. Arch ships both in one `libmtp` package; Debian splits the library from
`libmtp-runtime`, which the deb correctly names. Verify on a Fedora machine
before changing it.

### Upstream says these are not tools

The libmtp README, section "The Examples", is explicit:

> 1. They are examples, not tools. If they were intended for
>    day-to-day usage by commandline freaks, I would have
>    called them "tools" not "examples".

`mtp_client.dart` parses their human-readable output. `parseMtpFiles` reads the
lines `File ID: `, `Filename: `, `File size ` and `Parent ID: `. That format has
no stability promise from anyone.

The same README explains the `MtpFailure.staleSession` case the app already
handles:

> For example this means that a device may work the first time
> you run some command-line example like "mtp-detect" while
> subsequent runs fail.

The cause is one session per process. Three commands means three sessions. A
binding holds one session open across the listing and the transfer, which is
what upstream says the protocol wants.

**The shape to build.** `ffigen` over `libmtp.h`, then `LIBMTP_Get_Filelisting`,
`LIBMTP_Get_Folder_List` and `LIBMTP_Get_File_To_File`. The last one takes a
progress callback, which replaces the current per-batch progress with real
per-byte progress. `MtpToolRunner` is already an interface, so the seam for this
exists.

**What it costs.** `libmtp.so` stays a dependency; only the three commands go.
On Linux that changes `suggests: libmtp-runtime` into a library dependency.

**No Dart package exists.** pub.dev has `libusb` and `libusb_new` FFI wrappers
and no MTP implementation. Writing PTP/MTP over raw USB is not in scope.

**Order.** TQ-0029 brings MTP to macOS and Windows. Both tasks touch the same
file, and an FFI binding changes what TQ-0029 has to ship per platform: a
`libmtp` library instead of three commands. Settle this task first.

## The file manager — replace on Linux only

`open -R` on macOS and `explorer.exe /select,` on Windows ship with the OS.
Nothing to decide.

Linux is different. `xdg-utils` is a hard `depends` in all three package
formats, and `xdg-open` is given the **parent folder**, so Linux only opens a
folder while macOS and Windows select the file.

`org.freedesktop.FileManager1.ShowItems` selects the file and needs no binary.
It answered on this machine. Nautilus, Dolphin, Thunar, Nemo and PCManFM-Qt all
implement it, and it is D-Bus activatable.

**It costs nothing.** `dbus` 0.7.15 is already resolved in the tree, because
`file_picker_linux` depends on it. Promoting it to a direct dependency adds no
package. It is pure Dart, from Canonical, a verified publisher.

**Keep a fallback.** A session with no `FileManager1` provider still needs
`xdg-open` on the parent folder. So `xdg-utils` moves from `depends` to
`recommends`, and does not disappear.

## Recommendation

| Binary | Decision | New dependency |
| --- | --- | --- |
| `ffmpeg` | replace with libmpv | none |
| `ffprobe` | replace with a header parser | none |
| `mtp-*` commands | replace with an FFI binding to `libmtp.so` | none on pub.dev |
| `xdg-open` | replace with D-Bus `ShowItems`, keep as a fallback | `dbus`, already in the tree |
| `open`, `explorer.exe` | keep | none |

Every replacement here adds no pub.dev package that is not already resolved.
That is the reason to prefer replacement over declaration in all four cases.

## What is left to declare

After the work above, the deb and rpm `recommends: ffmpeg` goes, the
`suggests: libmtp*` becomes a library dependency, and `xdg-utils` drops to
`recommends`. The README "Optional Tools" table loses its FFmpeg and FFprobe
rows and its `pacman -S` line. `site/docs.html:180` and its FAQ entry "A video
has no thumbnail" go with them. `docs/releasing.md:168` stops naming `ffmpeg`
and `ffprobe` as the reason the macOS build leaves the App Sandbox; libmtp
alone, or nothing, then decides that.

## Suggested split

Each of these lands on its own. None blocks another.

1. **ffprobe to a header parser.** Smallest, measured, no FFI.
2. **xdg-open to D-Bus ShowItems.** Small, and it fixes Linux behaviour.
3. **ffmpeg to libmpv.** Needs the `vo=image` check on three platforms.
4. **The libmtp FFI binding.** Largest. Settle before TQ-0029.
5. **The packaging and docs sweep.** Last, after 1 to 4.

## Done when

- Every binary above has a decision recorded, with the reason.
- Each accepted replacement has its own task filed, with its scope.
- The Fedora `libmtp-examples` split is confirmed on a Fedora machine.
- The `image` VO is confirmed in the Windows and macOS libmpv builds.

---

## Notes

- 2026-09-21T21:54:27+02:00 — Filed from a full pass over lib/. Evidence is in the body; the measurements were taken on 2026-09-21 on this machine.

  Reproduce the ffprobe measurement: the prototype parser was Python, not Dart, and it is not committed. It reads MP4 moov/mvhd and Matroska Segment>Info>Duration with TimestampScale, then compares to ffprobe format=duration. 939 real files, 0 failures, max gap 67 ms.

  Two claims were tested, not assumed:
  - mpv --vo=null --frames=1 --screenshot-template=... wrote no file. A headless media_kit Player cannot screenshot.
  - mpv --vo=image --frames=1 wrote a 1934x1080 JPEG in 0.121 s, against 0.102 s for the ffmpeg call the app runs today.

  Read ~/Syncthing/games-screenshot-gallery read-only; nothing was modified.
