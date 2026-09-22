---
id: TQ-0029
title: Support Nintendo Switch and Switch 2 MTP on macOS
status: todo
priority: normal
labels:
  - feature
  - component/backend
  - component/build
  - security
depends_on:
  - TQ-0009
  - TQ-0068
created: 2026-09-20T16:33:09+02:00
updated: 2026-09-22T09:19:42+02:00
---

Enable direct USB/MTP album collection on macOS for the shared Nintendo Switch album source used by Nintendo Switch, Switch Lite, and Nintendo Switch 2. Keep copied-album folder import available as the fallback on every platform.

Research updated 2026-09-22. Windows support was split into TQ-0069 so each platform can choose its native transport and be accepted independently.

## Finding

Most import behavior is already shared and platform-neutral. The missing macOS piece is a transport that can discover the requested console, own an MTP/PTP session, enumerate its read-only album hierarchy, and download selected objects to staging.

Prototype Apple's ImageCaptureCore first. The Switch 2 has been observed upstream as a read-only hierarchical `Album` store using mostly generic PTP operations, which makes a camera-oriented framework plausible. Apple documents ImageCaptureCore for cameras and scanners rather than promising support for arbitrary MTP devices, so real-hardware proof is a mandatory decision gate.

If ImageCaptureCore cannot expose and download the console album reliably, bundle libmtp 1.1.23 or newer and libusb and call them in process. Do not require Homebrew or depend on `mtp-folders`, `mtp-files`, or `mtp-connect` being on PATH.

The adapter must serve both console sources. Nintendo uses USB vendor ID `057e`; the album-sharing product IDs are `201d` for Nintendo Switch / Switch Lite and `2061` for Nintendo Switch 2.

## Decision gate: ImageCaptureCore hardware spike

Use a real console in **System Settings → Data Management → Manage Screenshots and Videos → Copy to PC via USB Connection**, connected directly with a data-capable USB cable rather than through the dock.

The spike must establish all of the following before ImageCaptureCore is selected:

1. `ICDeviceBrowser` discovers the console and exposes stable USB vendor/product identity.
2. The app can open a device session and wait for the complete catalog.
3. Per-game folder hierarchy, filenames, media types, and file sizes are available.
4. One `_s.jpg` screenshot and one `_s.mp4` recording download successfully to an app-controlled staging directory.
5. The operation is read-only and offers no console-side delete behavior.
6. Empty albums, cancellation, busy-device behavior, disconnect, reconnect, and session cleanup are observable and mappable to actionable errors.
7. The same behavior works from a signed and notarized build, not only from Xcode.

If those checks pass, implement an ImageCaptureCore-backed Swift adapter through a Flutter macOS plugin or method channel.

## Shared architecture

Select the macOS adapter at application composition time. Do not scatter `Platform.isMacOS` branches through `NintendoSwitchAlbumSource`.

The native transport should own discovery and the complete session lifecycle. Prefer a scoped interface equivalent to `withDevice(selector, session => ...)` over unrelated finder/list/pull calls. The scope must guarantee cleanup and prevent a device-discovery result from racing a later open. It must also select the requested product ID deterministically when both console generations are connected.

The shared Dart source remains responsible for:

- accepting only original `_s.jpg` screenshots and `_s.mp4` clips;
- excluding `_c` copies and unsupported files;
- ignored-folder and already-imported checks;
- staging-size verification, import naming, progress, and cleanup;
- provider-specific warnings and copied-folder fallback.

Keep native object handles, ImageCaptureCore callback ordering, and any libmtp pointers out of the provider-facing API. Translate native failures to the existing MTP failure categories where the recovery action is the same; add distinct denied, unavailable, or disconnected results only when they allow better guidance.

## ImageCaptureCore implementation shape

The Swift adapter owns:

- `ICDeviceBrowser` discovery and VID/PID selection;
- `ICCameraDevice` session open/close and catalog readiness;
- folder and file traversal into platform-neutral metadata;
- file download with progress and cancellation;
- conversion of delegate callbacks into one completed Dart operation;
- cleanup in every success, empty-plan, cancellation, and error path.

Run blocking or long-running native work away from the Flutter UI thread and serialize access to a selected device session.

## Fallback: bundled libmtp and libusb

Use this route only if the hardware spike rejects ImageCaptureCore.

- Bundle libmtp 1.1.23 or newer because that release added Switch 2 `057e:2061` to its device table; bundle a compatible libusb as well.
- Resolve the libmtp FFI work described by TQ-0062 before implementing this branch. Use generated bindings plus a small C shim or a macOS native plugin rather than parsing example-program output.
- Detect raw devices, select the exact VID/PID, open one device session, enumerate and transfer within that session, and release it in a guaranteed cleanup path.
- Keep native calls off the UI isolate/thread and expose byte-level progress where available.
- Do not ship a solution that requires root, a privileged helper, a custom USB driver, or users detaching/replacing system drivers. If macOS cannot claim the interface safely, retain copied-folder import instead.

Upstream testing observed a macOS kernel driver attached to the Switch 2 interface. libusb documents extra authorization and interface-capture complications when a system driver owns a device, so this is a release risk to test early.

## macOS permissions and security

The previous task text assumed the application was sandboxed. That is no longer true: `docs/releasing.md` explicitly documents Developer ID distribution outside App Sandbox because the app starts child processes, and the current entitlements do not contain `com.apple.security.app-sandbox`.

Therefore:

- Do not add `com.apple.security.device.usb` for the current unsandboxed build; Apple defines it as an App Sandbox entitlement.
- If App Sandbox is restored later, add and validate the narrow USB entitlement in both debug and release configurations.
- The copied-folder picker and security-scoped bookmark flow is unrelated to direct USB/MTP and must not be presented as its permission mechanism.
- Hardened runtime is already enabled by the macOS packaging flow.
- Apple associates ImageCaptureCore photo importing with the Photos Library entitlement. Determine whether this download-to-staging use actually requires it by inspecting and testing a signed build; do not add it speculatively.

## Packaging and licensing for the fallback

If libmtp/libusb is selected:

- Build universal `arm64` and `x86_64` dylibs targeting the application's macOS 12 deployment target.
- Place them under `Contents/Frameworks`, use bundle-relative `@rpath` install names, and verify architectures and linked paths with `lipo` and `otool`.
- Sign nested dylibs before signing the app, then notarize and staple the complete package. `tool/package_macos.sh` already has the necessary inside-out dylib-signing structure.
- Preserve libmtp/libusb copyright and LGPL notices and provide the exact corresponding source, build scripts, and patches. Prefer dynamic linking; obtain a compliance review before release.

## User experience

- With no console connected or album sharing disabled, explain the exact console setting and direct-cable requirement.
- For a busy device, mention that Image Capture, Photos, OpenMTP, or another importer may own it.
- Do not ask the user to select an MTP folder; the console object hierarchy is not a mounted filesystem.
- Keep copied-album folder import available even when direct USB support is unavailable.
- Replace Linux-only settings and documentation language with capability-based guidance only after a macOS transport is available.

## Validation and done criteria

Real hardware acceptance is required on Apple Silicon and Intel Macs using a packaged release build on a clean machine.

1. Switch / Switch Lite (`057e:201d`) and Switch 2 (`057e:2061`) can each be selected reliably.
2. The console is detected only while album sharing is enabled.
3. Per-game folders, screenshots, recordings, names, and sizes enumerate correctly.
4. Original `_s` JPG and MP4 captures transfer; `_c` copies and unsupported files remain excluded.
5. Ignored folders and already-imported captures are skipped.
6. Transfers are read-only and temporary staging files are always cleaned up.
7. Empty albums, cancellation, disconnect/reconnect, stale sessions, concurrent access, and unavailable devices produce actionable results.
8. Connecting both console generations at once does not import from the wrong device.
9. The signed, notarized, and stapled application works without Homebrew, PATH dependencies, root access, or manually installed drivers.
10. Automated tests cover adapter selection, native metadata/error mapping, close-on-success and close-on-failure behavior, and preservation of shared filtering logic.
11. Copied-folder import continues to work on every platform.

## Sources

- [Nintendo: transfer Switch 2 captures via USB](https://www.nintendo.com/en-gb/Support/Troubleshooting/How-to-Transfer-Screenshots-and-Video-Captures-from-Nintendo-Switch-2-to-a-Computer-via-a-USB-Cable-2914249.html)
- [Apple: ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore)
- [Apple: ICDeviceBrowser](https://developer.apple.com/documentation/imagecapturecore/icdevicebrowser)
- [Apple: ICCameraDevice](https://developer.apple.com/documentation/imagecapturecore/iccameradevice)
- [Apple: USB device entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.usb)
- [Apple: Photos Library entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.photos-library)
- [Apple: Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [libmtp: Switch 2 device investigation](https://sourceforge.net/p/libmtp/bugs/1953/)
- [libmtp v1.1.23 release](https://github.com/libmtp/libmtp/releases/tag/libmtp-1-1-23)
- [libmtp v1.1.23 device table](https://raw.githubusercontent.com/libmtp/libmtp/v1.1.23/src/music-players.h)
- [libmtp API](https://github.com/libmtp/libmtp/blob/master/src/libmtp.h.in)
- [libusb macOS FAQ](https://github.com/libusb/libusb/wiki/FAQ)

---

## Notes

- 2026-09-22T09:13:48+02:00 — Scope note after TQ-0068: this task now covers both consoles. The Switch 2
  collection moved to the shared NintendoSwitchAlbumSource, so the MtpClient and
  UsbDeviceFinder seams named here are the same seams the first-generation
  Nintendo Switch uses. A macOS or Windows backend built against them serves both
  without further work; only the album product ID differs (057e:201d for the
  Switch and Switch Lite, 057e:2061 for the Switch 2), and each source already
  supplies its own.
- 2026-09-22T09:19:39+02:00 — Updated the research and split Windows implementation into TQ-0069. This task now covers macOS only, for both Nintendo Switch generations through the shared album source. Corrected the obsolete sandbox guidance: the current Developer ID build is outside App Sandbox, so com.apple.security.device.usb is not part of the present implementation plan. ImageCaptureCore remains the first hardware spike; bundled libmtp/libusb is the fallback.
