#!/bin/bash
# Builds and signs a local menu bar application bundle.
set -euo pipefail

signing_identity="${MEMORY_MENU_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" || "$signing_identity" == "-" ]]; then
  printf '%s\n' 'Set MEMORY_MENU_SIGNING_IDENTITY to a valid macOS signing identity.' >&2
  exit 2
fi

cd -- "$(dirname -- "$0")"
swift build --configuration release
binary_dir=$(swift build --configuration release --show-bin-path)
mkdir -p dist
staging=$(mktemp -d dist/.bundle.XXXXXX)
trap 'rm -rf -- "$staging"' EXIT
bundle="$staging/Smoke.app"
mkdir -p "$bundle/Contents/MacOS"
install -m 755 "$binary_dir/memory-menu" "$bundle/Contents/MacOS/memory-menu"
install -m 644 info.plist "$bundle/Contents/Info.plist"
ditto Resources "$bundle/Contents/Resources"
codesign --force --sign "$signing_identity" "$bundle"
codesign --verify --strict "$bundle"
# ditto replaces bundle files in place, preserving the local launch path.
ditto "$bundle" dist/Smoke.app
codesign --verify --strict dist/Smoke.app
printf '%s\n' "$PWD/dist/Smoke.app"
