---
id: TQ-0029
title: Support Nintendo Switch 2 MTP on macOS and Windows
status: todo
priority: normal
labels:
  - feature
  - component/backend
  - component/build
  - security
depends_on:
  - TQ-0009
created: 2026-09-20T16:33:09+02:00
updated: 2026-09-22T09:13:48+02:00
---

Extend the Nintendo Switch 2 provider so direct USB/MTP album collection works on macOS and Windows as well as Linux. Keep copied-album folder imports available on every platform.

Research date: 2026-09-20.

## Finding

Direct Nintendo Switch 2 imports are feasible on both platforms, but they should use platform-native transports behind the existing MtpClient and device-discovery seams. The capture filtering, ignored-folder handling, staging, transfer verification, import naming, and progress reporting in NintendoSwitch2Provider should remain shared.

The current implementation supports direct collection only on Linux through the libmtp command-line tools. It returns a platform warning on macOS and Windows. The macOS application remains sandboxed and currently has no USB entitlement.

## Windows: use Windows Portable Devices

Implement a native Windows Portable Devices (WPD) backend exposed to Dart through a Flutter Windows plugin or method channel.

WPD provides the required operations:

1. IPortableDeviceManager enumerates connected portable devices and exposes identifying information.
2. IPortableDeviceContent represents device content as a traversable object hierarchy.
3. IPortableDeviceContent::Transfer returns the resource interface used to read existing files.
4. The backend can stream selected captures to the staging paths supplied by the shared provider.

Use classic desktop WPD rather than making libmtp the primary Windows backend. This avoids requiring an external command-line runtime, libusb, or replacement USB drivers. The official libmtp Windows notes describe libusb dependencies and possible Zadig driver installation, which would add installation and device-driver friction that the native WPD stack avoids.

Do not assume the Linux USB identifiers are exposed in the same form by WPD. Real-hardware testing must establish stable properties for identifying the Switch 2 album-sharing mode.

## macOS: prototype ImageCaptureCore first

Build a small native ImageCaptureCore spike and test it with a Switch 2 in “Copy to a Computer” mode. ImageCaptureCore can discover camera-style devices and expose their folders, files, and metadata, but Apple documents camera and scanner support rather than generic MTP compatibility. The task must therefore verify whether the console appears as an ICCameraDevice before committing to this backend.

If ImageCaptureCore exposes the album:

- Implement the macOS MtpClient and device-discovery adapters with ImageCaptureCore.
- Open and close device sessions cleanly.
- Traverse folders, read file metadata, and copy only the files selected by the shared provider.

If ImageCaptureCore does not expose the album:

- Bundle libmtp and libusb with the application and call them in process through a native plugin.
- Do not require Homebrew and do not depend on mtp-* executables being present on PATH.
- Include the native libraries in signing and notarization.
- Review and satisfy libmtp's LGPL-2.1 redistribution and relinking obligations.

## macOS sandbox and permission behavior

Add com.apple.security.device.usb to both macOS entitlement files for direct USB access.

This is hardware access, not access to a filesystem folder. The existing folder picker and security-scoped bookmark flow applies only to copied-album folders and must not be reused or described as the permission mechanism for direct MTP. Apple states that the USB entitlement allows sandboxed apps to use USB device access APIs, while framework-specific requirements can still apply. The UI must not promise that macOS will present a folder-style permission dialog.

Preserve the sandbox. Do not add broad filesystem entitlements or disable App Sandbox.

## Architecture

Keep the provider-facing API platform-neutral:

- Linux: existing LibMtpClient plus LinuxSysfsUsbDeviceFinder.
- Windows: a WPD-backed MtpClient and WPD device finder.
- macOS: ImageCaptureCore-backed adapters if the hardware spike succeeds; otherwise bundled libmtp/libusb adapters.
- Shared NintendoSwitch2Provider: unchanged planning, filtering, importing, progress, and warning behavior.

Select adapters at application composition time. Do not add operating-system branches throughout NintendoSwitch2Provider beyond any temporary compatibility gate needed during implementation.

Platform adapters should translate native failures into the existing MtpFailure categories where possible. Add categories only for genuinely distinct actionable states such as denied hardware access.

## User experience

- With no console connected or sharing its album, return a warning explaining how to enable “Copy to a Computer” on the console.
- For a busy device, identify that another application may be using it.
- For denied or unavailable hardware access, explain the platform-specific recovery action.
- Do not ask the user to select an MTP folder: the console's object hierarchy is not a normal mounted filesystem.
- Retain the copied-album custom-folder fallback on macOS and Windows.

## Validation

Completion requires real Switch 2 acceptance testing on both macOS and Windows because neither Apple nor Microsoft documents Switch 2 compatibility specifically.

Verify on each platform:

1. The console is detected only while it is sharing the album.
2. The implementation uses stable device-identification properties.
3. Album folders, screenshots, and recordings are enumerated correctly.
4. Original _s JPG and MP4 captures transfer successfully; _c copies and unsupported files remain excluded.
5. Ignored folders and already-imported captures are skipped.
6. Transfers are read-only from the console and staged files are cleaned up.
7. Reconnects, stale sessions, concurrent access, unavailable devices, and permission failures produce actionable warnings or errors.
8. A packaged release build works without Homebrew, PATH dependencies, or manually installed USB drivers.
9. macOS remains sandboxed, signed, and notarizable.
10. Automated tests cover adapter selection and native-result/error mapping; shared provider tests continue to pass.

## Sources

- [Microsoft: Enumerating WPD devices](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/enumerating-devices)
- [Microsoft: Enumerating device content](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/enumerating-content)
- [Microsoft: IPortableDeviceContent::Transfer](https://learn.microsoft.com/en-us/windows/win32/api/portabledeviceapi/nf-portabledeviceapi-iportabledevicecontent-transfer)
- [Microsoft: Windows.Devices.Portable](https://learn.microsoft.com/en-us/uwp/api/windows.devices.portable)
- [Apple: ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore)
- [Apple: USB device entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.usb)
- [Apple: Configuring App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Apple: Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [libmtp official repository](https://github.com/libmtp/libmtp)
- [libmtp Windows build and driver notes](https://github.com/libmtp/libmtp/blob/master/README.windows.txt)
- [libmtp build dependencies](https://github.com/libmtp/libmtp/blob/master/INSTALL)
- [libmtp license](https://github.com/libmtp/libmtp/blob/master/COPYING)

---

## Notes

- 2026-09-22T09:13:48+02:00 — Scope note after TQ-0068: this task now covers both consoles. The Switch 2
  collection moved to the shared NintendoSwitchAlbumSource, so the MtpClient and
  UsbDeviceFinder seams named here are the same seams the first-generation
  Nintendo Switch uses. A macOS or Windows backend built against them serves both
  without further work; only the album product ID differs (057e:201d for the
  Switch and Switch Lite, 057e:2061 for the Switch 2), and each source already
  supplies its own.
