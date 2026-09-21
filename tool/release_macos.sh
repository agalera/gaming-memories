#!/usr/bin/env bash

# Attaches a signed and notarized macOS .dmg to an existing GitHub release and
# folds its checksum into that release's SHA256SUMS. The release workflow
# publishes the Linux and Windows downloads on its own; the macOS one is built
# here, on a machine that holds the Developer ID certificate, so the
# certificate never has to live in a repository secret.

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

tag="${TAG:-}"
dist_dir="${DIST_DIR:-dist}"
version="${GM_VERSION:-${tag#v}}"

if [[ -z "$tag" ]]; then
  echo "Set TAG to the released tag, for example TAG=v0.1.0." >&2
  exit 1
fi

dmg_path="$dist_dir/gaming-memories-$version-macos-universal.dmg"
dmg_name="$(basename "$dmg_path")"

if [[ ! -f "$dmg_path" ]]; then
  echo "No .dmg at $dmg_path. Run 'make package-macos' first." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "The GitHub CLI is required. Install it from https://cli.github.com/." >&2
  exit 1
fi

if ! gh release view "$tag" >/dev/null 2>&1; then
  echo "No GitHub release for $tag. Push the tag and let the workflow finish first." >&2
  exit 1
fi

# An unsigned or unstapled image is worse than no download at all: Gatekeeper
# refuses it and the user has no way to tell a broken build from a blocked one.
if ! spctl --assess --type open --context context:primary-signature "$dmg_path" >/dev/null 2>&1; then
  if [[ "${GM_ALLOW_UNSIGNED:-}" != "1" ]]; then
    echo "$dmg_name is not signed and stapled, so Gatekeeper would block it." >&2
    echo "Fix the signing, or set GM_ALLOW_UNSIGNED=1 to publish it anyway." >&2
    exit 1
  fi
  echo "Publishing $dmg_name although Gatekeeper would block it." >&2
fi

gh release upload "$tag" "$dmg_path" --clobber

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# The workflow wrote SHA256SUMS over the artifacts it had. Rebuild it with the
# .dmg line in place, dropping any line from an earlier upload of the same file.
if gh release download "$tag" --pattern SHA256SUMS --dir "$work_dir" >/dev/null 2>&1; then
  grep -v " $dmg_name\$" "$work_dir/SHA256SUMS" > "$work_dir/next" || true
else
  : > "$work_dir/next"
fi

(cd "$dist_dir" && shasum -a 256 "$dmg_name") >> "$work_dir/next"
sort -k2 "$work_dir/next" > "$work_dir/SHA256SUMS"

gh release upload "$tag" "$work_dir/SHA256SUMS" --clobber

echo "Attached $dmg_name to $tag and refreshed SHA256SUMS."
cat "$work_dir/SHA256SUMS"
