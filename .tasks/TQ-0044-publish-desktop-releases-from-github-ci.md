---
id: TQ-0044
title: Publish desktop releases from GitHub CI
status: in-progress
priority: normal
labels:
  - component/ci
  - component/build
  - chore
created: 2026-09-20T21:31:11+02:00
updated: 2026-09-21T14:58:33+02:00
---

# Release distribution for Windows, macOS, and Linux

Research date: 2026-09-20

## Goal

Publish a release from GitHub CI for each tag. The release holds these files:

1. Windows: one self-executing `.exe`. No installer.
2. macOS: a `.dmg` that holds the signed and notarized `.app`.
3. Linux: a `.deb`, an `.rpm`, and an Arch `.pkg.tar.zst`.

## Decisions

| # | Decision | Effect |
| --- | --- | --- |
| 1 | The project has a paid Apple Developer account. | Sign and notarize the macOS build. |
| 2 | There is no certificate for Windows, and none is planned. | Ship an unsigned `.exe`. Document the SmartScreen warning. |
| 3 | The Windows `.exe` starts the app directly. | Use the `7zSD.sfx` module with `RunProgram`. |
| 4 | Linux declares dependencies. It does not bundle them. | See "Linux dependencies" below for the reason. |
| 5 | The license is open. See "License" below. | Blocks the first release. |

## Findings

### The app needs external libraries and commands

`media_kit` loads libmpv at run time. It tries `libmpv.so`, `libmpv.so.2`,
then `libmpv.so.1`. See
`media_kit-1.2.6/lib/src/player/native/core/native_library.dart:56`.
`media_kit_libs_linux` bundles no library. Its CMake file sets
`media_kit_libs_linux_bundled_libraries` to an empty value.

Windows and macOS do not have this problem. `media_kit_libs_windows_video`
and `media_kit_libs_macos_video` download prebuilt libmpv binaries and put
them in the app bundle.

The app also starts these external commands:

- `exiftool` — `lib/services/exiftool_service.dart:15`
- `ffprobe` — `lib/services/video_metadata_service.dart:27`
- `ffmpeg` — `lib/services/thumbnail_service.dart:49`
- `xdg-open`, `open`, `explorer.exe` — `lib/services/screenshot_action_service.dart:33`
- libmtp `mtp-folders`, `mtp-files`, `mtp-connect` — `lib/services/mtp_client.dart:105`

These commands are optional. The Linux packages must list them as
recommended or optional dependencies, not as hard dependencies.

### Windows builds a folder, not one file

`flutter build windows --release` writes `build/windows/x64/runner/Release/`.
The folder holds the `.exe`, several `.dll` files, and a `data/` directory.
Flutter has no single-file build option. The request is open upstream in
flutter/flutter#105655 and flutter/flutter#81134.

The Flutter documentation also requires three Microsoft runtime libraries
beside the executable: `msvcp140.dll`, `vcruntime140.dll`, and
`vcruntime140_1.dll`.

### macOS runs in the App Sandbox

`macos/Runner/Release.entitlements` turns on `com.apple.security.app-sandbox`.
The bundle identifier is `dev.fmartingr.gamingMemories`. The deployment
target is macOS 12.0. A release build of `flutter build macos` produces a
universal binary for arm64 and x86_64.

## License

The license choice is not free. The app ships prebuilt libmpv binaries on
Windows and macOS, and those two builds do not carry the same license.

### macOS ships an LGPL build

`media_kit_libs_macos_video` downloads
`libmpv-xcframeworks_v0.6.0_macos-universal-video-default.tar.gz` from
`media-kit/libmpv-darwin-build`. See its `macos/Makefile`. That repository
documents the `default` flavour as LGPL-2.1. It builds FFmpeg without
`--enable-gpl` and without `--enable-nonfree`.

LGPL-2.1 allows a permissive app license. The library is dynamically linked,
and the app can stay under MIT.

### Windows ships a GPL build

`media_kit_libs_windows_video` downloads
`mpv-dev-x86_64-20230924-git-652a1dd.7z` from
`media-kit/libmpv-win32-video-build`. See its `windows/CMakeLists.txt:67`.
That archive comes from `zhongfly/mpv-winbuild`. That project publishes two
variants. The LGPL variant carries `lgpl` in its filename. This one does not,
so it is the GPL variant. It links x264 and x265, which are GPL-2.0-or-later.

Confidence is high, but the source repository is archived. Verify it directly:
build once on Windows, then read the license files that land beside
`libmpv-2.dll` in `build/windows/x64/runner/Release/`.

If the GPL build is confirmed, the distributed Windows `.exe` is a combined
work under GPL-2.0-or-later.

### All Dart packages are permissive

`crypto`, `path`, `path_provider`, `material_ui`, and `flutter_lints` are
BSD-3-Clause. `file_picker`, `forui`, `image`, `imclipboard`, `media_kit`,
`media_kit_video`, and all `media_kit_libs_*` packages are MIT. Every one of
them is compatible with GPL and with MIT.

### The external commands do not change the license

The app starts `ffmpeg`, `ffprobe`, `exiftool`, and the libmtp commands as
separate processes. It does not link them. Their licenses do not reach the
app.

### Three license options

**Option A — GPL-3.0-or-later. Recommended.**
It covers the GPL libmpv on Windows without extra work. Every dependency is
compatible. It is the normal choice for an app built on mpv. One limit: a
GPL app cannot go on the Mac App Store. The plan ships a `.dmg` directly, so
this limit does not apply today.

**Option B — MIT for the source, GPL for the Windows binary.**
This is legal and common. The obligation moves to the release: the Windows
download must carry the GPL text and an offer of the full source for libmpv,
FFmpeg, x264, and x265. It adds work to every release.

**Option C — MIT, and replace the Windows libmpv.**
Pin the `mpv-dev-lgpl-x86_64-*` archive instead. This needs a fork or a patch
of `media_kit_libs_windows_video`, and the patch must be carried forward on
every update of that package. The LGPL build also drops some features.

## Plan: Windows self-executing exe

Use a 7-Zip SFX module. The module joins three parts into one `.exe`:

1. `7zSD.sfx` from the 7-Zip Extra archive.
2. A config file with `RunProgram="gaming_memories.exe"`.
3. A `.7z` archive of the release folder.

At start, the module extracts the files to the temporary folder. It then
starts the app. It removes the temporary files after the app exits.

Steps for the job:

1. Run `flutter build windows --release`.
2. Copy the three Microsoft runtime libraries into the release folder.
3. Create a `.7z` archive of the release folder. `7z` is already on the runner.
4. Add `7zSD.sfx` to the repository, or fetch it in the job.
5. Join the three parts with a binary concatenation.
6. Publish the result as `gaming-memories-<version>-windows-x64.exe`.
7. Publish a plain `.zip` of the same folder as a second option.

Risks:

- The bundle holds libmpv and FFmpeg, so it is large. Measure the start
  delay from a cold temporary folder. If it is too slow, switch to the
  `7z.sfx` module. That module asks the user for a folder and does not start
  the app.
- The `.exe` is unsigned, so SmartScreen shows a warning. The README must
  tell the user to select "More info", then "Run anyway".

## Plan: macOS dmg

Steps for the job:

1. Run `flutter build macos --release`.
2. Import the Developer ID certificate into a temporary keychain.
3. Sign the `.app` with `codesign --options=runtime --deep --force`.
4. Build the `.dmg` with `create-dmg`. Homebrew supplies this tool.
5. Sign the `.dmg`.
6. Submit it with `xcrun notarytool submit --wait`.
7. Attach the ticket with `xcrun stapler staple`.

Required secrets:

- The Developer ID certificate as a base64 `.p12` file.
- The certificate password and a temporary keychain password.
- The Apple ID, an app-specific password, and the team identifier.

Risks to verify on a signed build:

- The hardened runtime can block the `media_kit` dynamic libraries. The
  entitlement `com.apple.security.cs.disable-library-validation` is the fix.
- The App Sandbox limits child processes. Confirm that `exiftool`, `ffmpeg`,
  and `ffprobe` still start from a signed and notarized build.

## Plan: Linux deb, rpm, and Arch packages

### Linux dependencies

The question was whether the app can bundle its Linux dependencies. It can
bundle almost none of them. The reasons, per dependency:

| Dependency | Can it be bundled? | Why |
| --- | --- | --- |
| GTK 3 | No | The Flutter Linux embedder links it. It must come from the distribution. |
| libmpv | Technically yes, but do not | It pulls in FFmpeg, libass, fontconfig, freetype, harfbuzz, ALSA, PulseAudio, Wayland, X11, and libplacebo. That set is an AppImage, not a `.deb`. A `.deb` that bundles a shared library is also an anti-pattern. |
| `xdg-utils` | No | It is a set of system scripts. Its whole purpose is system integration. |
| ffmpeg, ffprobe | Yes, but do not | A static build adds about 80 MB to every package. The tools are optional, and all three distributions ship them. |
| exiftool | No | It is a Perl script. It needs a Perl runtime. TQ-0028 already tracks its removal. |
| libmtp commands | No | They need udev rules and device permissions from the distribution. |

So the hard dependency set stays at three packages: GTK 3, libmpv, and
`xdg-utils`. All three are in Debian, Ubuntu, Fedora, and Arch. This is the
normal shape for a Linux desktop package.

`media_kit` supports a bundled libmpv through
`MediaKit.ensureInitialized(libmpv: path)` and through the
`LIBMPV_LIBRARY_PATH` environment variable. Keep this in mind for a later
AppImage. It is not needed for the three package formats.

An AppImage is the right format for a zero-dependency Linux download. Add it
as a fourth artifact later if users ask for it.

### Build

Build the bundle one time on `ubuntu-24.04`. The output folder is
`build/linux/x64/release/bundle/`.

Build dependencies for the runner:

    clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev

Use `nfpm` to make all three packages from that one bundle. `nfpm` is a
single Go binary. It supports deb, rpm, and Arch formats from one YAML file
with per-format dependency overrides. It needs no container and no target
distribution.

Do not use Fastforge (the new name of `flutter_distributor`) for Linux. Its
deb maker exposes no key for `Depends`. Its rpm maker exposes no key for
`Requires`. This app needs a libmpv dependency, so those makers do not fit.

### Package layout

- `/usr/lib/gaming-memories/` holds the bundle.
- `/usr/bin/gaming-memories` is a symbolic link to the executable.
- `/usr/share/applications/dev.fmartingr.gaming_memories.desktop` is a new file.
- `/usr/share/icons/hicolor/<size>/apps/dev.fmartingr.gaming_memories.png`
  holds the icons. Extend `tool/generate_desktop_icons.sh` to write them.
- `/usr/share/licenses/` or `/usr/share/doc/` holds the license file.

### Dependencies per format

| Format | Depends | Optional |
| --- | --- | --- |
| deb | `libgtk-3-0`, `libmpv2 \| libmpv1`, `xdg-utils` | `ffmpeg`, `libimage-exiftool-perl`, `libmtp-runtime` |
| rpm | `gtk3`, `mpv-libs`, `xdg-utils` | `ffmpeg`, `perl-Image-ExifTool`, `libmtp` |
| arch | `gtk3`, `mpv`, `xdg-utils` | `ffmpeg`, `perl-image-exiftool`, `libmtp` |

### The glibc floor

A bundle built on `ubuntu-24.04` needs glibc 2.39 or later. Debian 12 and
Ubuntu 22.04 cannot run it. A `debian:12` container lowers the floor to
glibc 2.36. Start on `ubuntu-24.04`. Move to the container only if a user
reports the problem.

An AUR `-bin` package is a later task. It is out of scope here.

## Plan: the GitHub CI workflow

Add `.github/workflows/release.yml`. Trigger it on a `v*` tag. Add a
`workflow_dispatch` trigger for a dry run that publishes no release.

Jobs:

1. `linux` on `ubuntu-24.04` — builds the bundle and the three packages.
2. `macos` on `macos-15` — builds, signs, and notarizes the `.dmg`.
3. `windows` on `windows-2025` — builds and joins the self-executing `.exe`.
4. `release` — collects the artifacts and creates the GitHub release.

Details:

- Use `subosito/flutter-action` with the `stable` channel. The project pins
  `stable` in `.fvmrc`. FVM is not needed on the runner.
- Read the version from the git tag. Pass `--build-name` and `--build-number`
  to each `flutter build` command.
- Write a `SHA256SUMS` file in the `release` job.
- Add `make package-linux`, `make package-macos`, and `make package-windows`
  targets. The workflow calls them. A developer can call them too.

## Acceptance criteria

1. A `LICENSE` file is in the repository. Every package carries it.
2. A `v*` tag creates a GitHub release with all five files and a
   `SHA256SUMS` file.
3. The Windows `.exe` starts the app on a clean Windows 11 machine. The
   start delay is measured and recorded in a note.
4. The macOS `.dmg` opens on a clean machine. Gatekeeper does not block it.
5. Video playback works on all three platforms after install.
6. `exiftool`, `ffmpeg`, and `ffprobe` still work from the installed builds.
7. The `.deb` installs on Ubuntu 24.04. `apt` pulls libmpv.
8. The `.rpm` installs on Fedora. `dnf` pulls `mpv-libs`.
9. The Arch package installs with `pacman -U`.
10. The app shows in the desktop menu with its icon on all three Linux
    formats.
11. The README documents the download, the install steps, and the
    SmartScreen warning on Windows.

## References

- Flutter Windows distribution files: https://docs.flutter.dev/platform-integration/windows/building
- Single exe request: https://github.com/flutter/flutter/issues/105655
- 7-Zip SFX modules: https://documentation.help/7-Zip/sfx.htm
- nfpm: https://nfpm.goreleaser.com/docs/configuration/
- Fastforge makers: https://github.com/leanflutter/flutter_distributor
- GitHub runner images: https://github.com/actions/runner-images
- macOS libmpv builds and flavours: https://github.com/media-kit/libmpv-darwin-build
- Windows libmpv builds: https://github.com/zhongfly/mpv-winbuild
- mpv license terms: https://github.com/mpv-player/mpv/blob/master/Copyright

---

## Notes

- 2026-09-20T21:36:43+02:00 — Decisions 1-3 are settled by the project owner: a paid Apple Developer account exists, there is no Windows certificate and none is planned, and the Windows exe starts the app directly.

  Decision 4 (bundle Linux dependencies) is researched and answered: almost nothing can be bundled. GTK 3 is linked by the Flutter embedder, xdg-utils is a set of system scripts, and libmpv drags in an AppImage-sized tree. The hard dependency set stays at gtk3, libmpv and xdg-utils.

  Decision 5 (license) is still open and blocks the first release. The research found that macOS ships an LGPL-2.1 libmpv but Windows ships a GPL one, so GPL-3.0-or-later is the recommended option.
- 2026-09-21T14:32:46+02:00 — Owner decisions, all four asked before implementation:

  1. License: GPL-3.0-or-later (option A). LICENSE added at the repository root.
  2. macOS signing secrets are not configured yet. The workflow expects MACOS_CERTIFICATE_P12, MACOS_CERTIFICATE_PASSWORD, MACOS_KEYCHAIN_PASSWORD, APPLE_ID, APPLE_APP_PASSWORD and APPLE_TEAM_ID, and docs/releasing.md documents how to produce each one. The macOS job builds an unsigned dmg when the certificate secret is absent so a dry run still produces an artifact.
  3. The App Sandbox is dropped from the macOS build so exiftool, ffmpeg, ffprobe and the libmtp tools can start. Mac App Store distribution is ruled out; direct dmg distribution is the plan.
  4. Verification stops at a workflow_dispatch dry run. No tag is pushed.

  Conflict found during implementation and resolved with the owner: dropping the App Sandbox breaks the security-scoped bookmark bridge TQ-0026 built, because bookmarkData(options: .withSecurityScope) and startAccessingSecurityScopedResource() are sandbox facilities. Outside the sandbox a plain path carries the same access, so createFolderAccessService() now returns PathFolderAccessService on every platform. MacOSFolderAccessService and the Swift bridge stay in the repository but are no longer wired up.
- 2026-09-21T14:58:33+02:00 — Dry run verified: https://github.com/fmartingr/gaming-memories/actions/runs/35601109661 — Version, Linux, macOS and Windows all green, Release correctly skipped.

  Two bugs the first dry run found and the second confirmed fixed:

  1. Linux: media_kit_video's CMake links PkgConfig::mpv, so libmpv-dev is a build dependency, not just a runtime one. libmedia_kit_video_plugin.so carries a DT_NEEDED on libmpv.so.2, so the deb lost its 'libmpv1' alternative.
  2. Windows: 7zSD.sfx is not in the 7-Zip Extra package and has not been since 7-Zip 19. It ships in the LZMA SDK as bin/7zSD.sfx. RunProgram now uses the %%T form.

  FINDING — the license research in this task's body is wrong. It says the Windows build ships a GPL libmpv, with 'high' confidence, and that was the main argument for GPL-3.0-or-later. The shipped libmpv-2.dll says otherwise. Its embedded build configuration reads -Dgpl=false for mpv and --disable-gpl --disable-nonfree --enable-version3 for FFmpeg, and every FFmpeg library in it reports 'LGPL version 3 or later'. FFmpeg derives that from CONFIG_GPL at build time, so it is conclusive. Neither x264 nor x265 is linked; the x264 strings in the library are mpv's h264 decoder options and its SEI parsing. Both the Windows and macOS libmpv builds are LGPL and dynamically linked, so a permissive license for this source was available too. GPL-3.0-or-later is still valid and is shipped; the owner may want to revisit it now the premise is corrected. docs/releasing.md records the check under 'What the builds ship'.

  Measured, not assumed: the Linux bundle references no glibc symbol newer than 2.34 and no versioned libstdc++ symbol. The floor is libmpv.so.2, not the runner's glibc 2.39. The README and docs were corrected.

  Artifact checks on the dry run's downloads: deb declares Depends libgtk-3-0, libmpv2, xdg-utils with the recommends and suggests intact and a 46-file bundle; rpm installs its license under /usr/share/licenses; Arch package has depend gtk3/mpv/xdg-utils and no optdepend, which nfpm cannot express. The macOS dmg holds a universal x86_64+arm64 app with the Applications symlink, ad-hoc signed as expected with no certificate secrets, and entitlements carrying no app-sandbox. The Windows exe is a PE32 stub of 128000 bytes followed by the config and a 24 MB LZMA2 payload at offset 128105; the zip carries msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll and LICENSE.txt.

  Acceptance criteria 3 to 10 need real machines and are not verified: the Windows start delay from a cold temp folder, Gatekeeper on a clean Mac, video playback, the external commands from installed builds, and the three Linux installs. Criterion 4 also needs the six macOS secrets, which are not configured yet.
