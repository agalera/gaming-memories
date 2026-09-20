# Gaming Memories

Gaming Memories is a desktop media library for video games. It collects images and videos into platform and game albums.

The app includes these functions:

- A timeline that shows all media by date.
- An album tree that groups media by platform, game, and nested folder.
- Video thumbnails, duration details, and video playback.
- Settings for the library folder and provider folder.
- Diablo IV, Guild Wars 2, Hytale, Minecraft, PlayStation 4, PlayStation 5, and Steam providers.
- SHA-1 collision names that prevent file loss.

## Requirements

- Flutter 3.47.0 or later.
- Linux, macOS, or Windows.

FFmpeg and FFprobe are optional command-line tools. The app uses them to create video thumbnails and read video duration.

The app can play videos without these tools. It uses a current `.thumb.jpg` sidecar when one is available.

The Guild Wars 2 and PlayStation 4 providers require ExifTool. They use it to read screenshot dates.

PlayStation 4 and PlayStation 5 require a folder exported from the console. The PlayStation 5 provider uses FFprobe, when available, to date a clip from its start instead of the end time in its filename.

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

On macOS and Linux, Hytale is discovered in `Pictures/Hytale Screenshots`.
Its provider can also save the bundled Hytale cover in the library album.

Minecraft launcher screenshots are discovered on Windows, macOS, and Linux.
On Linux, both supported Flatpak screenshot layouts are scanned too.

Select the collect action in the page header to import media.

## Verify the project

```sh
make check
```
