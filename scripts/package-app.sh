#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=13.0
app="$PWD/dist/OverSlay.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build
for arch in arm64 x86_64; do
  swift build --configuration release --arch "$arch" --scratch-path ".build/$arch"
  bin_path=$(swift build --configuration release --arch "$arch" --scratch-path ".build/$arch" --show-bin-path)
  cp "$bin_path/OverSlay" "build/OverSlay-$arch"
  # SwiftPM resource bundles are siblings of the executable on macOS.
  while IFS= read -r -d '' resource; do
    ditto "$resource" "$app/Contents/MacOS/$(basename "$resource")"
  done < <(find "$bin_path" -maxdepth 1 -name '*.bundle' -type d -print0)
done
lipo -create build/OverSlay-arm64 build/OverSlay-x86_64 -output "$app/Contents/MacOS/OverSlay"
chmod 755 "$app/Contents/MacOS/OverSlay"
test -x "$app/Contents/MacOS/OverSlay"
cp packaging/Info.plist "$app/Contents/Info.plist"
iconset="build/OverSlay.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" packaging/OverSlay.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" packaging/OverSlay.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/OverSlay.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-1}" "$app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md LICENSE "$app/Contents/Resources/"
cp docs/reference/clickplay/LICENSE "$app/Contents/Resources/ClickPlay-LICENSE.txt"
git rev-parse HEAD > "$app/Contents/Resources/build-commit.txt"
plutil -lint "$app/Contents/Info.plist"
lipo "$app/Contents/MacOS/OverSlay" -verify_arch arm64 x86_64
# SwiftPM resource bundles live beside the executable and must be signed before the app.
while IFS= read -r -d '' resource_bundle; do
  codesign --force --sign - "$resource_bundle"
done < <(find "$app/Contents/MacOS" -maxdepth 1 -name '*.bundle' -type d -print0)
codesign --force --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"
cp docs/INSTALL.md dist/READ-ME-FIRST.md
ditto -c -k --sequesterRsrc --keepParent "$app" dist/OverSlay-macOS-universal.zip
stage=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/OverSlay.app"
ln -s /Applications "$stage/Applications"
cp docs/INSTALL.md "$stage/READ-ME-FIRST.txt"
hdiutil create -volname OverSlay -srcfolder "$stage" -format UDZO -ov dist/OverSlay-macOS-universal.dmg
hdiutil verify dist/OverSlay-macOS-universal.dmg
(cd dist && shasum -a 256 OverSlay-macOS-universal.zip OverSlay-macOS-universal.dmg > SHA256SUMS.txt)
