---
id: TQ-0069
title: Support Nintendo Switch and Switch 2 MTP on Windows
status: todo
priority: normal
labels:
  - feature
  - component/backend
  - component/build
depends_on:
  - TQ-0009
  - TQ-0068
created: 2026-09-22T09:18:01+02:00
updated: 2026-09-22T09:18:07+02:00
---

Enable direct USB/MTP album collection on Windows for the shared Nintendo Switch album source used by Nintendo Switch, Switch Lite, and Nintendo Switch 2. Keep copied-album folder import available as the fallback on every platform.

Split from TQ-0029 on 2026-09-22 so Windows and macOS can be implemented and accepted independently.

## Finding

Use the native Windows Portable Devices (WPD) stack rather than libmtp as the primary Windows transport. WPD is the operating-system MTP path and avoids shipping libusb, requiring external command-line tools, or asking users to replace USB drivers.

The adapter must serve both console sources. Nintendo uses USB vendor ID `057e`; the album-sharing product IDs are `201d` for Nintendo Switch / Switch Lite and `2061` for Nintendo Switch 2. Do not assume WPD exposes those identifiers exactly as Linux sysfs does: establish the stable WPD identity properties with real hardware before finalizing selection.

## Native adapter

Implement a Windows Flutter plugin or method-channel adapter around classic desktop WPD:

- `IPortableDeviceManager` enumerates devices and exposes identifying properties.
- `IPortableDeviceContent` traverses the album object hierarchy.
- `IPortableDeviceContent::Transfer` obtains the stream for an existing capture.
- The adapter writes selected files to staging paths supplied by Dart and reports progress.
- The adapter owns device opening, one scoped session, content traversal, transfer cancellation, and cleanup.

Do not expose raw COM ordering requirements to the album source. Initialize COM on the worker thread that uses WPD, keep blocking enumeration and transfers off the Flutter UI thread, and release streams and device objects on every success and failure path.

## Shared architecture

Select the Windows adapter at application composition time. Do not add Windows branches throughout `NintendoSwitchAlbumSource`.

The shared Dart source remains responsible for:

- accepting only original `_s.jpg` screenshots and `_s.mp4` clips;
- excluding `_c` copies and unsupported files;
- ignored-folder and already-imported checks;
- staging-size verification, import naming, progress, and cleanup;
- provider-specific warnings and the copied-folder fallback.

Prefer a scoped, session-owning transport interface over independent discovery/list/pull calls. It must select the requested console deterministically, especially when a Switch and Switch 2 are connected at the same time.

Translate WPD and COM failures into the existing MTP failure categories where they remain meaningful. Add distinct categories only when the recovery action differs, such as access denied or device disconnected.

## User experience

- When no console is available, explain how to enable **System Settings → Data Management → Manage Screenshots and Videos → Copy to PC via USB Connection** and connect the console directly with a data-capable USB cable.
- When another application owns the device, identify it as a busy-device condition.
- Do not ask the user to select an MTP folder; WPD content is not a mounted filesystem.
- Preserve copied-album folder import as the no-USB fallback.

## Validation

Real Nintendo hardware is required because Microsoft does not document either console specifically.

Verify on a packaged Windows build:

1. Switch / Switch Lite (`057e:201d`) and Switch 2 (`057e:2061`) can each be selected reliably.
2. The console is available only while album sharing is enabled.
3. Per-game folders, screenshots, recordings, names, and file sizes map correctly from WPD objects.
4. Original `_s` JPG and MP4 captures transfer; `_c` copies and unsupported files do not.
5. Ignored folders and already-imported captures are skipped.
6. Transfers are read-only from the console and staging files are cleaned up.
7. Empty albums, cancellation, mid-transfer disconnect, reconnect, stale sessions, and concurrent access produce actionable results.
8. Connecting both console generations at once does not import from the wrong device.
9. The packaged app works on a clean supported Windows machine without Homebrew-style dependencies, PATH tools, libusb drivers, Zadig, or administrator privileges.
10. Automated tests cover adapter selection, native result/error mapping, session cleanup, and preservation of shared filtering behavior.

## Sources

- [Nintendo: transfer Switch 2 captures via USB](https://www.nintendo.com/en-gb/Support/Troubleshooting/How-to-Transfer-Screenshots-and-Video-Captures-from-Nintendo-Switch-2-to-a-Computer-via-a-USB-Cable-2914249.html)
- [Microsoft: Enumerating WPD devices](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/enumerating-devices)
- [Microsoft: Enumerating device content](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/enumerating-content)
- [Microsoft: IPortableDeviceContent::Transfer](https://learn.microsoft.com/en-us/windows/win32/api/portabledeviceapi/nf-portabledeviceapi-iportabledevicecontent-transfer)
- [Microsoft: Windows Portable Devices SDK](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/windows-portable-devices)
- [libmtp Windows build and driver notes](https://github.com/libmtp/libmtp/blob/master/README.windows.txt)
- [libmtp v1.1.23 device table](https://raw.githubusercontent.com/libmtp/libmtp/v1.1.23/src/music-players.h)
