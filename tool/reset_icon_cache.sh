#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

warn() {
  echo "$*" >&2
}

reset_macos() {
  local lsregister app found=0
  lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

  if [[ ! -x "$lsregister" ]]; then
    warn "lsregister not found; skipping Launch Services refresh."
    return 0
  fi

  while IFS= read -r -d '' app; do
    found=1
    touch "$app"
    "$lsregister" -f "$app"
    echo "Re-registered $app"
  done < <(find "$project_root/build/macos/Build/Products" -maxdepth 2 -name '*.app' -print0 2>/dev/null)

  for app in "$@"; do
    found=1
    touch "$app"
    "$lsregister" -f "$app"
    echo "Re-registered $app"
  done

  if [[ "$found" -eq 0 ]]; then
    warn "No .app bundle found under build/macos/Build/Products; build the app first."
  fi

  killall Dock 2>/dev/null || true
  killall Finder 2>/dev/null || true
  echo "Dock and Finder restarted."
}

reset_linux() {
  local dir refreshed=0

  for dir in "$HOME/.local/share/icons/hicolor" /usr/share/icons/hicolor; do
    [[ -d "$dir" ]] || continue
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
      gtk-update-icon-cache --force --ignore-theme-index "$dir" 2>/dev/null &&
        echo "Refreshed icon cache in $dir" && refreshed=1
    fi
  done

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null &&
      echo "Refreshed desktop database." && refreshed=1
  fi

  if [[ "$refreshed" -eq 0 ]]; then
    warn "Nothing to refresh; install gtk-update-icon-cache and desktop-file-utils for installed-icon caches."
  fi

  echo "The runtime window icon is read from data/app_icon.png in the bundle, so no cache applies to it."
}

reset_windows() {
  local cache_root="${LOCALAPPDATA:-$HOME/AppData/Local}"

  if command -v ie4uinit.exe >/dev/null 2>&1; then
    ie4uinit.exe -show || true
    ie4uinit.exe -ClearIconCache || true
  else
    warn "ie4uinit.exe not found; deleting cache files only."
  fi

  rm -f "$cache_root/IconCache.db" 2>/dev/null || true
  rm -f "$cache_root/Microsoft/Windows/Explorer/iconcache"*.db 2>/dev/null || true
  rm -f "$cache_root/Microsoft/Windows/Explorer/thumbcache"*.db 2>/dev/null || true

  if command -v taskkill >/dev/null 2>&1; then
    taskkill //F //IM explorer.exe >/dev/null 2>&1 || true
    ( explorer.exe >/dev/null 2>&1 & ) || true
    echo "Explorer restarted."
  else
    warn "taskkill not found; sign out and back in to finish clearing the cache."
  fi
}

case "$(uname -s)" in
  Darwin) reset_macos "$@" ;;
  Linux) reset_linux ;;
  MINGW* | MSYS* | CYGWIN*) reset_windows ;;
  *)
    warn "Unsupported platform: $(uname -s)"
    exit 1
    ;;
esac

echo "Icon cache reset. Quit and relaunch the app to pick up the new icon."
