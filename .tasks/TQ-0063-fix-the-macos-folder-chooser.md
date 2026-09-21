---
id: TQ-0063
title: Fix the macOS folder chooser
status: done
priority: urgent
labels:
  - component/frontend
created: 2026-09-21T22:12:02+02:00
updated: 2026-09-21T22:19:05+02:00
---

## Problem

On macOS the Settings folder **Choose** button does nothing: no dialog, no error.
Linux and Windows work.

## Cause

`PathFolderAccessService.choose` calls `FilePicker.getDirectoryPath`.
`file_picker_darwin` runs an App Sandbox entitlement check before showing
`NSOpenPanel` and fails with `ENTITLEMENT_NOT_FOUND` unless the app declares
`com.apple.security.files.user-selected.read-only`/`read-write`. This build is
unsandboxed (Developer ID, runs ffmpeg/ffprobe) and declares neither, so the
check fails, `getDirectoryPath` swallows the `PlatformException` and returns
`null`, which `chooseFolder` reads as a cancelled pick.

`file_picker_darwin.getDirectoryPath` also ignores `dialogTitle` and
`initialDirectory` entirely, so even past the entitlement check the panel would
open at an arbitrary folder and the automatic provider flows that compare the
selection against an expected path would fail.

## Fix

Route macOS through the Runner's own `NSOpenPanel`, which honours the title and
the initial directory, and keep file_picker for Linux and Windows.

---

## Notes

- 2026-09-21T22:19:05+02:00 — Reproduced on the macOS debug build: the picker logged
  "[FilePickerDarwin] Could not resolve directory path: Either the Read-Only or
  Read-Write entitlement is required for this action." and returned null, which
  chooseFolder reads as a cancelled pick, so the button did nothing and said
  nothing.

  Fixed by adding a choosePath method to the Runner's folder-access channel and
  injecting the chooser into PathFolderAccessService: macOS gets the NSOpenPanel,
  Linux and Windows keep file_picker unchanged.

  Verified end to end on the rebuilt macOS app: Choose opens a folders-only panel
  titled "Choose the media library folder", the selection reaches the settings
  ("Settings saved.", the library switches to "Up to date") and lands in
  gaming-memories.json as outputPath. flutter analyze, 194 Dart tests and the
  Xcode RunnerTests all pass.
