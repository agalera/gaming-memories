# Gaming Memories

Gaming Memories is a desktop screenshot library for video games. It collects screenshots from provider folders and stores them in platform and game albums.

This first version supports the Diablo IV provider. The app includes these functions:

- A timeline that shows all screenshots by date.
- An album tree that groups screenshots by platform and game.
- Settings for the library folder and provider folder.
- A Diablo IV import that uses the file modification date for each name.
- SHA-1 collision names that prevent screenshot loss.

## Requirements

- Flutter 3.47.0 or later.
- Linux, macOS, or Windows.

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

Select the collect action in the page header to import screenshots.

## Verify the project

```sh
make check
```
