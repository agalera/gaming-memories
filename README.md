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
  Nintendo Switch albums.
- **Safe imports:** SHA-1 collision suffixes prevent one capture from
  overwriting another.
- **Publish to the web:** Render the library as a static HTML gallery and
  upload it to your own host over SSH.

## Supported Sources

| Source | Collected from | Extra setup |
| --- | --- | --- |
| **Battle.net** | Installed Diablo IV and World of Warcraft capture folders | None |
| **Guild Wars 2** | Game screenshot folder | None |
| **Hytale** | `Pictures/Hytale Screenshots` | None |
| **Minecraft** | Launcher screenshot folders, including supported Linux Flatpak layouts | None |
| **Nintendo Switch** | Copied album folder on every platform, or direct USB on Linux | libmtp tools for USB |
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
| **libmtp** | Collecting directly from a Nintendo Switch or Nintendo Switch 2 over USB on Linux | Import a copied album folder instead |

For direct Nintendo Switch collection, install the `mtp-folders`,
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

Nintendo Switch and Nintendo Switch 2 each have their own source, and both
import original `_s.jpg` screenshots and `_s.mp4` clips while ignoring `_c`
duplicates. Individual album folders, including the folder for captures taken
outside a game, can be excluded in Settings. Collect from one console at a
time: the libmtp tools answer for whichever console they open first.

PlayStation 4 and PlayStation 5 use folders exported from the console. When
FFprobe is available, the PlayStation 5 source dates a clip from its start
rather than the end time stored in its filename.

## Publishing

Gaming Memories can render the library as a static website and upload it to a
host you control. Turn it on under **Settings → Publish**; a **Publish** button
then appears in the sidebar, above **Settings**.

Each album becomes one page, with folder tiles, a screenshot and clip filter, a
sort toggle, a light and dark theme that follows the reader's system setting,
and a lightbox with keyboard, click and swipe navigation. The pages
are written to a folder of the app's own, so nothing is ever written between
your captures. The upload merges the two: captures and their thumbnails from the
library first, then the pages from that folder, so a page never arrives before
the media it links to. While a publish runs the sidebar shows its progress and
offers a stop.

Platform tiles use covers bundled with the app, matched to the platform folder
by name: Android, Game Boy, Game Boy Advance, Game Boy Color, Nintendo Switch,
Nintendo Switch 2, PC, Pico-8, PlayStation 4, PlayStation 5 and Super Nintendo.
A `cover.*` file you put in a platform folder yourself is used instead, and a
platform with neither falls back to a capture from below it. Game albums keep
using the cover their source saved beside them.

The whole library is published, minus the platforms and albums listed under
**Excluded albums**. With mirroring on, anything the gallery no longer holds is
removed from the host too.

### Connecting

| Setting | What it is |
| --- | --- |
| **Host**, **Port**, **User** | Where the upload connects, over SSH |
| **Remote folder** | The absolute path your web server serves |
| **Sign in with** | Automatic key, a key file, or a password |
| **File and folder permissions** | Applied as each file is written; `644` and `755` are what `chmod -R u=rwX,go=rX` leaves behind |

### Signing in

| Choice | What it uses |
| --- | --- |
| **Automatic key** | Whatever this machine already has, the same way `ssh` finds it |
| **Key file** | One key you pick, and only that one |
| **Password** | The account password on the host |

Automatic is the default and needs nothing configured. It reads `~/.ssh/config`
for the host you are publishing to and honours `IdentityAgent`, `IdentityFile`
and `IdentitiesOnly`, including anything pulled in by `Include`. An agent set
up that way — 1Password, Secretive, gpg-agent — is found even though a windowed
app inherits no `SSH_AUTH_SOCK` from your shell. Failing all that, it falls back
to `SSH_AUTH_SOCK` and then to the usual `~/.ssh/id_ed25519`, `id_ecdsa`,
`id_rsa`, `id_dsa`.

A key your agent already holds never asks for its passphrase. `Match` blocks are
skipped, because their conditions cannot be evaluated here, and `HostName`,
`User` and `Port` come from the fields above rather than from the config.

No secret is ever saved. Only the path to a key file is stored; a passphrase or
a password is asked for the first time you publish after starting the app, and
kept in memory until it closes.

### Host keys

The first time you publish to a host, its key is taken on trust and remembered,
the way answering `ssh`'s prompt with `yes` does. If that key ever changes, the
publish refuses and uploads nothing: either the server was rebuilt, or
something is pretending to be it.

A host `ssh` already knows is not asked about again — `~/.ssh/known_hosts` is
read, including hashed entries and any `UserKnownHostsFile` your config names
for that host. Keys accepted here are kept beside the settings rather than
written into your `known_hosts`, which stays yours; rsync maintains that file
itself.

### rsync or SFTP

**Automatic** uses rsync when this machine has version 3 or newer and nothing
has to be typed for it, because it compares the whole tree in far fewer round
trips. Otherwise the upload goes over SFTP, which needs no external program and
works on every platform, Windows included.

Publishing with a password always goes over SFTP: rsync would have to type it
on a terminal the app does not have.

The `rsync` that macOS ships is openrsync. It accepts the flags a mirrored
publish needs and then ignores them, which would leave captures you deleted on
the host, so it is never used — install rsync 3 if you want the faster path
there.

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
