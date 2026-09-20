# Gaming Memories

Gaming Memories is a desktop media library for video games. It collects images and videos into platform and game albums.

The app includes these functions:

- A timeline that shows all media by date.
- An album tree that groups media by platform, game, and nested folder.
- Video thumbnails, duration details, and video playback.
- Settings for the library folder and provider folder.
- Diablo IV and Steam providers.
- SHA-1 collision names that prevent file loss.

## Requirements

- Flutter 3.47.0 or later.
- Linux, macOS, or Windows.

FFmpeg and FFprobe are optional command-line tools. The app uses them to create video thumbnails and read video duration.

The app can play videos without these tools. It uses a current `.thumb.jpg` sidecar when one is available.

## Run the app

```sh
make setup
make run
```

Use `make run-macos` or `make run-windows` on the related operating system.
Run `make help` to see all development commands.

Open **Settings** in the sidebar. Select a library folder. Enable Diablo IV and select its screenshot folder.

On Windows, you can leave the Diablo IV folder empty. The provider scans these default folders:

- `Pictures\Diablo IV`
- `Documents\Diablo IV\Screenshots`

Select the collect action in the page header to import media.

## Verify the project

```sh
make check
```
