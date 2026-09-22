<div align="center">

<img src="assets/logo.png" alt="Gaming Memories logo" width="200">

# Gaming Memories

**Bring every game capture into one beautiful library.**

A desktop media library that collects screenshots and clips into browsable
platform and game albums.

[![Built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
![Platforms](https://img.shields.io/badge/platforms-Linux%20%7C%20macOS%20%7C%20Windows-F97316)

[Website](https://fmartingr.github.io/gaming-memories/) ·
[Downloads](https://github.com/fmartingr/gaming-memories/releases) ·
[Documentation](https://fmartingr.github.io/gaming-memories/docs.html)

</div>

## About

Gaming Memories brings captures from your games and consoles into one local,
organized collection. Browse everything chronologically, move through albums by
platform and game, or open a capture for a closer look without leaving the app.

## Highlights

- **One unified timeline:** Browse screenshots and clips from every enabled
  source in capture-date order.
- **Structured albums:** Navigate by platform, game, and nested folders.
- **Rich image viewing:** Zoom with a pinch, double click, or modifier scroll,
  then pan naturally with a trackpad.
- **Video support:** See generated thumbnails and durations, then play clips
  directly in the library.
- **Automatic collection:** Import from PC games, Steam, console exports, and
  Nintendo Switch 2 albums.
- **Safe imports:** SHA-1 collision suffixes prevent one capture from
  overwriting another.

## Supported Sources

| Source | Collected from | Extra setup |
| --- | --- | --- |
| **Battle.net** | Installed Diablo IV and World of Warcraft capture folders | None |
| **Guild Wars 2** | Game screenshot folder | None |
| **Hytale** | `Pictures/Hytale Screenshots` | None |
| **Minecraft** | Launcher screenshot folders, including supported Linux Flatpak layouts | None |
| **Nintendo Switch 2** | Copied album folder on every platform, or direct USB on Linux | libmtp tools for USB |
| **PlayStation 4** | Folder exported from the console | None |
| **PlayStation 5** | Folder exported from the console | FFprobe recommended for clip dates |
| **Steam** | Local screenshots and the optional online gallery | Steam Web API key; SteamID64 for online imports |

## Download and Install

Every release publishes a build for each desktop platform on the
[releases page](https://github.com/fmartingr/gaming-memories/releases). A
`SHA256SUMS` file beside the downloads carries the checksum of each one.

### Windows

Download `gaming-memories-<version>-windows-x64.exe` and run it. The file is a
self-executing archive: it unpacks the app to a temporary folder, starts it,
and clears that folder when the app exits. There is nothing to install and
nothing to uninstall.

**The download is not code signed**, so Windows SmartScreen shows a blue
"Windows protected your PC" panel the first time you run it. Select **More
info**, then **Run anyway**.

`gaming-memories-<version>-windows-x64.zip` holds the same build as a plain
folder. Unpack it anywhere and run `gaming_memories.exe` if you would rather
keep the app in one place.

### macOS

Download `gaming-memories-<version>-macos-universal.dmg`, open it, and drag
**Gaming Memories** into **Applications**. The app is signed with a Developer
ID certificate and notarized by Apple, so Gatekeeper opens it without a
warning. The build is universal and runs natively on Apple silicon and Intel.

The macOS download is signed on a machine that holds the certificate rather
than in CI, so it is attached a few minutes after the Linux and Windows ones.

macOS asks for permission the first time the app reads a folder inside
Desktop, Documents, Downloads, or a removable volume. Allow it once and the
grant persists.

### Linux

Three formats are published. Each one declares GTK 3, libmpv, and
`xdg-utils` as dependencies, so the package manager pulls what the app needs.

| Distribution | Command |
| --- | --- |
| Debian, Ubuntu | `sudo apt install ./gaming-memories_<version>-1_amd64.deb` |
| Fedora, RHEL | `sudo dnf install ./gaming-memories-<version>-1.x86_64.rpm` |
| Arch | `sudo pacman -U gaming-memories-<version>-1-x86_64.pkg.tar.zst` |

The packages are built on Ubuntu 24.04. They need glibc 2.34 or newer and a
libmpv that provides `libmpv.so.2`, which mpv 0.36 and newer do. Ubuntu 24.04,
Debian 13, Fedora 40, and a current Arch all meet both. The app lands in
`/usr/lib/gaming-memories` with a `gaming-memories` command in `/usr/bin` and
an entry in the desktop menu.

The deb and rpm packages recommend `ffmpeg` and suggest the libmtp
tools. See [Optional Tools](#optional-tools) for what each one adds. The Arch
package format cannot carry optional dependencies, so install them yourself:

```sh
sudo pacman -S ffmpeg libmtp
```

## Build From Source

### Requirements

- Flutter 3.47.0 or newer.
- Linux, macOS, or Windows with its Flutter desktop toolchain installed.
- [FVM](https://fvm.app/) for the included development commands.

### Build and run

```sh
git clone https://github.com/fmartingr/gaming-memories.git
cd gaming-memories
make setup
make run
```

`make run` targets Linux by default. Use the matching command for another
desktop platform:

| Platform | Command |
| --- | --- |
| Linux | `make run-linux` |
| macOS | `make run-macos` |
| Windows | `make run-windows` |

### Set up your library

1. Open **Settings** from the sidebar.
2. Choose the folder where Gaming Memories should keep its library.
3. Enable and configure the sources you use.
4. Select the collect action in the page header to import your media.

## Optional Tools

Gaming Memories works without every helper below; each one unlocks a specific
piece of metadata or collection behavior.

| Tool | Used for | Without it |
| --- | --- | --- |
| **FFmpeg** | Generating video thumbnails | Existing `.thumb.jpg` sidecars are used when available |
| **FFprobe** | Reading video duration and the start time of PlayStation 5 clips | Videos still play; PlayStation 5 clips use the end time in their filename |
| **libmtp** | Collecting directly from a Nintendo Switch 2 over USB on Linux | Import a copied album folder instead |

For direct Nintendo Switch 2 collection, install the `mtp-folders`,
`mtp-files`, and `mtp-connect` commands. Open **Album** on the console, choose
**Copy to a Computer**, connect it by USB, and close or eject it from any file
manager first. Only one program can use the MTP device at a time.

## Source Notes

### Battle.net

Battle.net discovers installed Diablo IV and World of Warcraft variants and
imports each game into its own album. On Windows, Diablo IV screenshots are
read from:

- `Pictures\Diablo IV`
- `Documents\Diablo IV\Screenshots`

On macOS, automatic World of Warcraft discovery asks for access to its
installation folder. JPG and PNG screenshots keep the date from their
filename; TGA screenshots are converted to PNG for gallery compatibility.

### Hytale and Minecraft

Hytale is discovered automatically on macOS and Linux in
`Pictures/Hytale Screenshots`, and its source can save the bundled cover in
the library album.

Minecraft launcher screenshots are discovered on Windows, macOS, and Linux.
Both supported Flatpak screenshot layouts are included on Linux.

### Consoles

Nintendo Switch 2 imports original `_s.jpg` screenshots and `_s.mp4` clips
while ignoring `_c` duplicates. Individual album folders, including the folder
for captures taken outside a game, can be excluded in Settings.

PlayStation 4 and PlayStation 5 use folders exported from the console. When
FFprobe is available, the PlayStation 5 source dates a clip from its start
rather than the end time stored in its filename.

## Development

Run the complete formatting, analysis, and test suite with:

```sh
make check
```

Use `make help` to see every available development and build command.

Use `make help` to see every available development and build command,
including the `package-linux`, `package-macos`, and `package-windows` targets
that produce the release artifacts. [docs/releasing.md](docs/releasing.md)
describes how a release is cut and which secrets the workflow needs.

## License

Gaming Memories is released under the
[GNU General Public License v3.0 or later](LICENSE).

The Windows and macOS builds ship a prebuilt libmpv, and both are LGPL builds
with no GPL-only component linked in. Every Dart and Flutter package the app
depends on is BSD-3-Clause or MIT. See
[docs/releasing.md](docs/releasing.md#what-the-builds-ship) for how that was
checked.
