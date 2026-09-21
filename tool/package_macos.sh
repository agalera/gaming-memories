#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

app_path="build/macos/Build/Products/Release/Gaming Memories.app"
dist_dir="${DIST_DIR:-dist}"
version="${GM_VERSION:-$(sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)}"
dmg_path="$dist_dir/gaming-memories-$version-macos-universal.dmg"
identity="${MACOS_SIGN_IDENTITY:-}"

if [[ -z "$version" ]]; then
  echo "Could not read a version. Set GM_VERSION." >&2
  exit 1
fi

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found at $app_path." >&2
  echo "Run 'make build-macos BUILD_MODE=release' first." >&2
  exit 1
fi

mkdir -p "$dist_dir"
rm -f "$dmg_path"

if [[ -n "$identity" ]]; then
  # The hardened runtime rejects a nested library whose signature the outer
  # seal invalidated, so the bundle is signed from the inside out. --deep
  # would instead stamp the app's entitlements onto every nested binary.
  while IFS= read -r framework; do
    codesign --force --timestamp --options runtime --sign "$identity" "$framework"
  done < <(find "$app_path/Contents/Frameworks" -maxdepth 1 -name '*.framework' 2>/dev/null)

  while IFS= read -r dylib; do
    codesign --force --timestamp --options runtime --sign "$identity" "$dylib"
  done < <(find "$app_path/Contents/Frameworks" -name '*.dylib' 2>/dev/null)

  codesign --force --timestamp --options runtime \
    --entitlements macos/Runner/Release.entitlements \
    --sign "$identity" "$app_path"
  codesign --verify --strict --verbose=2 "$app_path"
else
  echo "MACOS_SIGN_IDENTITY is not set. Building an unsigned .dmg." >&2
  echo "Gatekeeper will block this build on another machine." >&2
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install it with 'brew install create-dmg'." >&2
  exit 1
fi

staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT
cp -R "$app_path" "$staging_dir/"

# create-dmg exits non-zero when it cannot sign the image it just built, so the
# result is checked by hand below instead of by set -e.
create-dmg \
  --volname "Gaming Memories" \
  --window-pos 200 120 \
  --window-size 620 400 \
  --icon-size 128 \
  --icon "Gaming Memories.app" 160 200 \
  --app-drop-link 450 200 \
  --hdiutil-quiet \
  "$dmg_path" \
  "$staging_dir" || true

if [[ ! -f "$dmg_path" ]]; then
  echo "create-dmg did not produce $dmg_path." >&2
  exit 1
fi

if [[ -z "$identity" ]]; then
  echo "Unsigned .dmg written to $dmg_path."
  exit 0
fi

codesign --force --timestamp --sign "$identity" "$dmg_path"

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" || -z "${APPLE_TEAM_ID:-}" ]]; then
  echo "APPLE_ID, APPLE_APP_PASSWORD or APPLE_TEAM_ID is missing." >&2
  echo "Signed .dmg written to $dmg_path, but it is not notarized." >&2
  exit 0
fi

xcrun notarytool submit "$dmg_path" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

xcrun stapler staple "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"

echo "Signed and notarized .dmg written to $dmg_path."
