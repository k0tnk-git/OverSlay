#!/bin/bash
# Launch the delivered app via LaunchServices, not swift run. No injected input.
set -euo pipefail
app="$1"
report="$2"
mkdir -p "$(dirname "$report")"
exec > >(tee "$report") 2>&1
sw_vers
uname -m
stat -f '%Sp %N' "$app/Contents/MacOS/OverSlay"
test -x "$app/Contents/MacOS/OverSlay"
plutil -lint "$app/Contents/Info.plist"
# SwiftPM may choose a resource-bundle name; locate the actual catalogs instead of assuming it.
en_catalog="$(find "$app/Contents" -type f -path '*/en.lproj/Localizable.strings' -print -quit)"
ru_catalog="$(find "$app/Contents" -type f -path '*/ru.lproj/Localizable.strings' -print -quit)"
test -n "$en_catalog" && test -n "$ru_catalog"
plutil -lint "$en_catalog" "$ru_catalog"
echo 'PASS: packaged English and Russian localization catalogs are present and valid'
codesign --verify --deep --strict --verbose=2 "$app"
lipo -info "$app/Contents/MacOS/OverSlay"
otool -L "$app/Contents/MacOS/OverSlay"
launcher=""
cleanup() {
  # This script runs only in a fresh, dedicated CI runner.
  pkill -TERM -x OverSlay || true
  if [ -n "$launcher" ]; then wait "$launcher" || true; fi
}
trap cleanup EXIT
open -n -W "$app" &
launcher=$!
sleep 5
if ! pgrep -x OverSlay; then
  echo 'FAIL: app did not stay alive after LaunchServices launch'
  find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'OverSlay*' -type f -exec cat {} \; 2>/dev/null || true
  exit 1
fi
echo 'PASS: LaunchServices accepted the app and its process stayed alive for 5 seconds'
echo 'NOT RUN: downloaded-file Gatekeeper approval, input permissions, game input and UI interaction'
