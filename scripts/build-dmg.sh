#!/bin/zsh
# Builds a universal, ad-hoc signed Nephele.app and packs dist/Nephele-<version>.dmg (drag-to-Applications installer).
# Needs Xcode 26+ and XcodeGen. Run from anywhere.
set -e
cd "$(dirname "$0")/.."
ver=$(grep -o 'MARKETING_VERSION: "[^"]*"' project.yml | cut -d'"' -f2)
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)
xcodegen generate >/dev/null
rm -rf build/release && mkdir -p build/release dist
xcodebuild build -project Nephele.xcodeproj -scheme Nephele -configuration Release -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CURRENT_PROJECT_VERSION="$build" CONFIGURATION_BUILD_DIR="$PWD/build/release" >build/release/xcodebuild.log 2>&1 \
  || { tail -30 build/release/xcodebuild.log; exit 1; }
app=build/release/Nephele.app
codesign --force --deep --sign - --options runtime "$app"
codesign --verify --deep --strict "$app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$ver" ] || { echo "Version mismatch in the built app"; exit 1; }
stage=$(mktemp -d)
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
out="dist/Nephele-$ver.dmg"
rm -f "$out"
hdiutil create -volname "Nephele $ver" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$out" >/dev/null
rm -rf "$stage"
(cd dist && shasum -a 256 "Nephele-$ver.dmg" > "Nephele-$ver.dmg.sha256")
echo "$out"
