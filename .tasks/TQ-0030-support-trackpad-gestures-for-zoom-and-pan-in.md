---
id: TQ-0030
title: Support trackpad gestures for zoom and pan in the detail view
status: done
priority: normal
labels:
  - feature
  - component/frontend
created: 2026-09-20T16:34:38+02:00
updated: 2026-09-20T17:20:59+02:00
---

## Goal

The screenshot detail view already wraps the image in an `InteractiveViewer`
(`lib/screens/screenshot_detail_page.dart:71`), which only responds to
click-drag and mouse wheel. On macOS the natural input is the trackpad, so
zooming and panning should work with the same gestures every other macOS image
viewer uses.

## Scope

- **Pinch to zoom** — two-finger pinch scales the image around the pointer.
- **Two-finger scroll pans** the image while zoomed in, both axes.
- **Double tap / double click** toggles between fit-to-view and a zoomed step.
- **Modifier + scroll** (⌘ or ⌃ + two-finger scroll) also zooms, matching
  Preview.
- Keep the existing `minScale` / `maxScale` bounds and reset the transform when
  the media changes (navigating to another screenshot must not keep the
  previous zoom).
- Video previews are out of scope — gestures apply to images only.

## Notes on implementation

`InteractiveViewer` exposes `trackpadScrollCausesScale`, `scaleEnabled` and
`panEnabled`, and Flutter routes macOS trackpad pinches as pointer pan/zoom
events, so most of this may be configuration rather than a custom gesture
recognizer. Verify what the current widget already does on a real trackpad
before writing new gesture code, and use an explicit
`TransformationController` for the reset and double-tap behaviour.

## Acceptance

- Pinch, two-finger pan and double tap all work in the detail view on macOS.
- Zoom resets when switching to another media item.
- Widget tests cover the transformation controller reset; gesture behaviour is
  verified manually.

---

## Notes

- 2026-09-20T17:20:59+02:00 — Implemented in lib/screens/screenshot_detail_page.dart: _MediaPreview is now stateful with a TransformationController, an animated double-tap zoom (2.5x around the tapped point, clamped to the viewport), a reset when the media path changes, and trackpadScrollCausesScale driven by a HardwareKeyboard handler so Cmd/Ctrl + two-finger scroll zooms while a plain two-finger scroll pans.

  Trackpad pinch needed no extra code: InteractiveViewer's scale recognizer already consumes macOS pan/zoom pointer events. Confirmed in a scratch test that a pinch inside a scrollable loses only its first increment while the gesture arena resolves, so the narrow (<900px) ListView layout still zooms.

  Tests added to test/widget_test.dart: 'zooms the detail image with a double tap and resets it' and 'pans, pinches and modifier-zooms with trackpad gestures' (runs on a 1600x1000 surface, so it covers the wide Row layout). Full suite: 114 passing, analyze clean. Gestures on real hardware are still unverified - no trackpad in this environment.
