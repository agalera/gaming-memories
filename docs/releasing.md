# Releasing

`.github/workflows/release.yml` builds and publishes every release. It runs on
a `v*` tag and can also be started by hand for a dry run that builds the same
artifacts and publishes nothing.

## Cut a release

```sh
git tag v1.2.0
git push origin v1.2.0
```

The tag name without its leading `v` becomes the version passed to every
`flutter build` as `--build-name`. The workflow run number becomes
`--build-number`. `pubspec.yaml` is not read during a release, so its version
line does not have to be bumped for the tag to take effect.

The run produces six files and attaches them to a GitHub release:

| File | Platform |
| --- | --- |
| `gaming-memories-<version>-windows-x64.exe` | Windows, self-executing |
| `gaming-memories-<version>-windows-x64.zip` | Windows, plain folder |
| `gaming-memories-<version>-macos-universal.dmg` | macOS, signed and notarized |
| `gaming-memories_<version>-1_amd64.deb` | Debian, Ubuntu |
| `gaming-memories-<version>-1.x86_64.rpm` | Fedora, RHEL |
| `gaming-memories-<version>-1-x86_64.pkg.tar.zst` | Arch |

`SHA256SUMS` carries the checksum of each one.

## Dry run

Start **Release** from the Actions tab with `workflow_dispatch`. The `version`
input defaults to `0.0.0`. The three build jobs run and upload their artifacts
to the run, and the `release` job is skipped, so nothing is published.

## Build a package locally

```sh
make package-linux      # needs nfpm
make package-macos      # needs create-dmg
make package-windows    # needs 7-Zip and PowerShell
```

Each target builds the release app first and writes to `dist/`. Set `VERSION`
to override the version taken from `pubspec.yaml`.

`make package-macos` produces an unsigned `.dmg` when `MACOS_SIGN_IDENTITY` is
not set, which is enough for a local check but is blocked by Gatekeeper on
another machine.

## Secrets

The macOS job signs and notarizes only when `MACOS_CERTIFICATE_P12` is present.
Without it the job still builds a `.dmg`, unsigned, and says so in its log. The
other five secrets are read only on the signing path.

| Secret | What it holds |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | The Developer ID Application certificate and its private key, as a base64 `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | The password set when exporting that `.p12` |
| `MACOS_KEYCHAIN_PASSWORD` | Any string. It locks the temporary keychain the job creates and deletes |
| `APPLE_ID` | The Apple ID of the developer account |
| `APPLE_APP_PASSWORD` | An app-specific password for that Apple ID |
| `APPLE_TEAM_ID` | The ten-character team identifier |

### Export the certificate

1. In Keychain Access, find **Developer ID Application: …** under **My
   Certificates**. Create one at
   [developer.apple.com](https://developer.apple.com/account/resources/certificates/list)
   if it is missing.
2. Right-click it, choose **Export**, and save a `.p12` with a password. The
   export has to include the private key, so select the certificate row rather
   than the key row.
3. Encode it and copy the result into the secret:

   ```sh
   base64 -i DeveloperID.p12 | pbcopy
   ```

### Create the app-specific password

Sign in at [appleid.apple.com](https://appleid.apple.com), open **Sign-In and
Security**, then **App-Specific Passwords**, and generate one. The team
identifier is on the [membership
page](https://developer.apple.com/account#MembershipDetailsCard).

## How each platform is built

### Linux

One `flutter build linux --release` produces `build/linux/x64/release/bundle`.
`nfpm` turns that one bundle into all three package formats from
`packaging/linux/nfpm.yaml`, with per-format dependency names.

`libmpv-dev` is a build dependency as well as a runtime one: the Linux build of
`media_kit_video` links `PkgConfig::mpv`, so the binary carries a `DT_NEEDED`
on `libmpv.so.2` rather than loading it only through `dlopen`.

GTK 3, libmpv, and `xdg-utils` are hard dependencies. None of the three can be
bundled: GTK 3 is linked by the Flutter embedder, `xdg-utils` is a set of
system scripts, and libmpv pulls in FFmpeg, libass, fontconfig, freetype,
harfbuzz, ALSA, PulseAudio, Wayland, X11, and libplacebo — an AppImage's worth
of tree, and a shared library inside a `.deb` is an anti-pattern besides.

FFmpeg, ExifTool, and the libmtp tools are optional, so the deb and rpm
packages declare them as recommends and suggests. The Arch package format has
no equivalent, so the README asks the user to install them.

The runner is `ubuntu-24.04`, but its own glibc is not the floor. The built
binaries reference no glibc symbol newer than 2.34 and no versioned libstdc++
symbol at all, so the binding constraint is `libmpv.so.2`, which means mpv 0.36
or newer. Measure both again after a Flutter upgrade rather than assuming the
runner sets the floor:

```sh
strings -a build/linux/x64/release/bundle/lib/*.so \
        build/linux/x64/release/bundle/gaming_memories |
  grep -oE 'GLIBC_2\.[0-9]+' | sort -uV | tail -1
```

### macOS

`flutter build macos --release` produces a universal `Gaming Memories.app`.
`tool/package_macos.sh` signs it from the inside out — nested frameworks and
dylibs first, then the bundle with its entitlements — because the outer seal
otherwise invalidates the nested signatures under the hardened runtime.
`create-dmg` builds the image, `notarytool submit --wait` sends it to Apple,
and `stapler staple` attaches the ticket.

The release build runs **outside the App Sandbox**. The sandbox blocks the
child processes the app depends on, so `exiftool`, `ffmpeg`, `ffprobe`, and the
libmtp tools cannot start from a sandboxed build. Dropping it is normal for
Developer ID distribution and rules out the Mac App Store, which is not a
target. Because security-scoped bookmarks are a sandbox facility, macOS uses
the same plain-path folder access as Linux and Windows; see
`lib/services/folder_access_service.dart`.

`com.apple.security.cs.disable-library-validation` stays in the entitlements so
the hardened runtime loads the `media_kit` libraries.

### Windows

`flutter build windows --release` writes a folder, not one file, and Flutter
has no single-file option. `tool/package_windows.ps1` copies `msvcp140.dll`,
`vcruntime140.dll`, and `vcruntime140_1.dll` beside the executable, packs the
folder into a `.7z`, and joins three parts end to end into the published
`.exe`:

1. `7zSD.sfx`, the 7-Zip self-extracting module.
2. `packaging/windows/sfx-config.txt`, which names the program to start.
3. The `.7z` archive.

At start the module unpacks to a temporary folder, runs
`gaming_memories.exe` from it, and clears the folder when the app exits.

`tool/fetch_sfx_module.ps1` downloads the LZMA SDK and checks it against a
pinned SHA-256 before taking `bin/7zSD.sfx` out of it. The SDK is where that
module ships; the 7-Zip Extra package has not carried an SFX module since
7-Zip 19. The module is not committed to this repository.

The payload is packed with LZMA2 alone. `7zSD.sfx` is the small C build of
SFXSetup, and keeping a branch coder out of the archive keeps it to one
decoder.

There is no Windows code signing certificate and none is planned, so the
download is unsigned and SmartScreen warns on first run. The README tells the
user to select **More info**, then **Run anyway**.

`packaging/windows/sfx-config.txt` needs CRLF line endings. `.gitattributes`
marks it so git leaves them alone.

## What the builds ship

The project is GPL-3.0-or-later. The prebuilt libmpv in the Windows and macOS
builds was checked against that, because a GPL-only libmpv would have forced
the license rather than left it open.

`media_kit_libs_windows_video` downloads
`mpv-dev-x86_64-20230924-git-652a1dd.7z`, whose filename carries no `lgpl`
marker. That marker is not what decides it. The build configuration inside the
shipped `libmpv-2.dll` reads `-Dgpl=false` for mpv and
`--disable-gpl --disable-nonfree --enable-version3` for FFmpeg, and every
FFmpeg library in it reports its license as `LGPL version 3 or later`. FFmpeg
derives that string from `CONFIG_GPL` at build time, so it is conclusive.
Neither x264 nor x265 is linked; the `x264` strings in the library belong to
mpv's h264 decoder options and its SEI parsing.

`media_kit_libs_macos_video` downloads the `default` flavour from
`media-kit/libmpv-darwin-build`, documented as LGPL-2.1 and built without
`--enable-gpl`.

Both libraries are dynamically linked, so an MIT or other permissive license
for this source would also have been possible. Re-check this after either
`media_kit_libs_*` package changes the archive it downloads:

```sh
strings -a libmpv-2.dll | grep -oE 'LGPL version [0-9]+ or later|GPL version [0-9]+ or later'
```
