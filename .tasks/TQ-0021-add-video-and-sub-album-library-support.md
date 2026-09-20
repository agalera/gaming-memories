---
id: TQ-0021
title: Add video and sub-album library support
status: done
priority: high
labels:
  - frontend
  - backend
created: 2026-09-20T01:51:40+02:00
updated: 2026-09-20T02:05:18+02:00
---

Scan image and video files from each game folder. Preserve nested folders as selectable sub-albums. Generate compatible video thumbnails and read video duration. Show videos in the gallery and play videos on the details page. Keep selection and scroll state. Add tests for video files and nested albums.

---

## Notes

- 2026-09-20T02:05:18+02:00 — Added a unified media model with image and video kinds. The scanner preserves each nested folder as a selectable sub-album. It supports MP4, AVI, MKV, and WebM files. It reuses the old .thumb.jpg and .metadata.json sidecars. It uses FFmpeg and FFprobe when a sidecar needs a refresh. The gallery shows video state and duration. The details page uses media_kit for playback. Tests: 25 passed. Flutter analysis: no issues. Linux release build: passed.
