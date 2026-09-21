#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

bundle_dir="build/linux/x64/release/bundle"
dist_dir="${DIST_DIR:-dist}"
version="${GM_VERSION:-$(sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)}"

if [[ -z "$version" ]]; then
  echo "Could not read a version. Set GM_VERSION." >&2
  exit 1
fi

if [[ ! -x "$bundle_dir/gaming_memories" ]]; then
  echo "Linux bundle not found at $bundle_dir." >&2
  echo "Run 'make build-linux BUILD_MODE=release' first." >&2
  exit 1
fi

if ! command -v nfpm >/dev/null 2>&1; then
  echo "nfpm is required. Install it from https://nfpm.goreleaser.com/install/." >&2
  exit 1
fi

mkdir -p "$dist_dir"

for packager in deb rpm archlinux; do
  GM_VERSION="$version" nfpm package \
    --config packaging/linux/nfpm.yaml \
    --packager "$packager" \
    --target "$dist_dir/"
done

echo "Linux packages written to $dist_dir."
