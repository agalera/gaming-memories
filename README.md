# Gaming Memories

Gaming Memories is a desktop media library for video games. It collects images and videos into platform and game albums.

The app includes these functions:

- A timeline that shows all media by date.
- An album tree that groups media by platform, game, and nested folder.
- Video thumbnails, duration details, and video playback.
- An image detail view that zooms with a trackpad pinch, a double click, or a modifier scroll, and pans with a two-finger scroll.
- Settings for the library folder and provider folder.
- Battle.net, Guild Wars 2, Hytale, Minecraft, Nintendo Switch 2, PlayStation 4, PlayStation 5, and Steam providers.
- SHA-1 collision names that prevent file loss.

## Requirements

- Flutter 3.47.0 or later.
- Linux, macOS, or Windows.

FFmpeg and FFprobe are optional command-line tools. The app uses them to create video thumbnails and read video duration.

The app can play videos without these tools. It uses a current `.thumb.jpg` sidecar when one is available.

The Guild Wars 2 and PlayStation 4 providers require ExifTool. They use it to read screenshot dates.

Nintendo Switch 2 can read a copied album folder on any platform. On Linux it
can also collect directly over USB with the `mtp-folders`, `mtp-files`, and
`mtp-connect` commands from libmtp.

PlayStation 4 and PlayStation 5 require a folder exported from the console. The PlayStation 5 provider uses FFprobe, when available, to date a clip from its start instead of the end time in its filename.

## Run the app

```sh
make setup
make run
```

Use `make run-macos` or `make run-windows` on the related operating system.
Run `make help` to see all development commands.

Open **Settings** in the sidebar. Select a library folder, then enable the providers you use.

The Battle.net provider detects installed Diablo IV and World of Warcraft variants and imports each game into its own album. On Windows, Diablo IV screenshots use these locations:

- `Pictures\Diablo IV`
- `Documents\Diablo IV\Screenshots`

On macOS, automatic World of Warcraft discovery asks for access to its installation folder. World of Warcraft JPG and PNG screenshots keep the date from their filename; TGA screenshots are converted to PNG for gallery compatibility.

On macOS and Linux, Hytale is discovered in `Pictures/Hytale Screenshots`.
Its provider can also save the bundled Hytale cover in the library album.

Minecraft launcher screenshots are discovered on Windows, macOS, and Linux.
On Linux, both supported Flatpak screenshot layouts are scanned too.

Nintendo Switch 2 imports original `_s.jpg` screenshots and `_s.mp4` clips,
while ignoring `_c` duplicates. In direct Linux mode, open Album on the console,
choose Copy to a Computer, and connect it by USB. Close or eject it from any
file manager first because only one program can use the MTP device at a time.
Album folders can be excluded in Settings, including the console's folder for
captures taken outside a game.

Select the collect action in the page header to import media.

## Verify the project

```sh
make check
```
