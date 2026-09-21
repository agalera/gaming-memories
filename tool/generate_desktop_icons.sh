#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_icon="$project_root/assets/logo.png"
macos_icon_dir="$project_root/macos/Runner/Assets.xcassets/AppIcon.appiconset"
windows_icon="$project_root/windows/runner/resources/app_icon.ico"
linux_icon="$project_root/linux/runner/resources/app_icon.png"
hicolor_dir="$project_root/packaging/linux/icons/hicolor"
hicolor_name="dev.fmartingr.gaming_memories"

# macOS 26 scales the whole 1024 canvas into the plate it draws behind every
# legacy icon, so artwork on a transparent canvas ends up inset twice and reads
# tiny in the Dock. Baking the plate into the canvas keeps the artwork
# edge-to-edge. Radius and inset follow the 1024 icon grid.
macos_plate_color="${MACOS_PLATE_COLOR:-#f5f5f5}"
macos_plate_radius="${MACOS_PLATE_RADIUS:-230}"
macos_art_size="${MACOS_ART_SIZE:-870}"

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick is required. Install it and make sure 'magick' is available." >&2
  exit 1
fi

if [[ ! -f "$source_icon" ]]; then
  echo "Source icon not found: $source_icon" >&2
  exit 1
fi

mkdir -p "$macos_icon_dir" "$(dirname "$windows_icon")" "$(dirname "$linux_icon")"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

magick "$source_icon" -trim +repage "$work_dir/art.png"

magick -size 1024x1024 xc:none -colorspace sRGB -fill "$macos_plate_color" \
  -draw "roundrectangle 0,0,1023,1023,$macos_plate_radius,$macos_plate_radius" \
  \( "$work_dir/art.png" -resize "${macos_art_size}x${macos_art_size}" \) \
  -gravity center -composite \
  "$work_dir/macos_master.png"

for size in 16 32 64 128 256 512 1024; do
  magick "$work_dir/macos_master.png" -filter Lanczos -resize "${size}x${size}" \
    "$macos_icon_dir/app_icon_${size}.png"
done

magick "$source_icon" -filter Lanczos \
  -define icon:auto-resize=256,128,64,48,32,24,16 "$windows_icon"

magick "$source_icon" -filter Lanczos -resize 512x512 "$linux_icon"

# The Linux packages install into the hicolor theme, which is what a desktop
# menu reads. The .desktop file names the icon "dev.fmartingr.gaming_memories".
rm -rf "$hicolor_dir"
for size in 16 32 48 64 128 256 512; do
  icon_dir="$hicolor_dir/${size}x${size}/apps"
  mkdir -p "$icon_dir"
  magick "$source_icon" -filter Lanczos -resize "${size}x${size}" \
    "$icon_dir/$hicolor_name.png"
done

echo "Desktop icons generated from assets/logo.png."
