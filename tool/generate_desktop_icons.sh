#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_icon="$project_root/assets/logo.png"
macos_icon_dir="$project_root/macos/Runner/Assets.xcassets/AppIcon.appiconset"
windows_icon="$project_root/windows/runner/resources/app_icon.ico"
linux_icon="$project_root/linux/runner/resources/app_icon.png"

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick is required. Install it and make sure 'magick' is available." >&2
  exit 1
fi

if [[ ! -f "$source_icon" ]]; then
  echo "Source icon not found: $source_icon" >&2
  exit 1
fi

mkdir -p "$macos_icon_dir" "$(dirname "$windows_icon")" "$(dirname "$linux_icon")"

for size in 16 32 64 128 256 512 1024; do
  magick "$source_icon" -filter Lanczos -resize "${size}x${size}" \
    "$macos_icon_dir/app_icon_${size}.png"
done

magick "$source_icon" -filter Lanczos \
  -define icon:auto-resize=256,128,64,48,32,24,16 "$windows_icon"

magick "$source_icon" -filter Lanczos -resize 512x512 "$linux_icon"

echo "Desktop icons generated from assets/logo.png."
