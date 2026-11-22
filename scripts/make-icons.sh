#!/bin/bash
# Renders assets/logo.svg into the macOS app icon set. Run from the repo root.
set -euo pipefail
SVG="assets/logo.svg"
SET="Nephele/Assets.xcassets/AppIcon.appiconset"
[ -f "$SVG" ] || { echo "missing $SVG" >&2; exit 1; }
TMP="$(mktemp -d)"
swiftc -O tools/render-svg.swift -o "$TMP/render-svg"
mkdir -p "$SET"
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" \
            "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" \
            "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  set -- $spec
  "$TMP/render-svg" "$SVG" "$SET/$2" "$1"
done
cat > "$SET/Contents.json" <<'JSON'
{
  "images": [
    {"idiom":"mac","scale":"1x","size":"16x16","filename":"icon_16x16.png"},
    {"idiom":"mac","scale":"2x","size":"16x16","filename":"icon_16x16@2x.png"},
    {"idiom":"mac","scale":"1x","size":"32x32","filename":"icon_32x32.png"},
    {"idiom":"mac","scale":"2x","size":"32x32","filename":"icon_32x32@2x.png"},
    {"idiom":"mac","scale":"1x","size":"128x128","filename":"icon_128x128.png"},
    {"idiom":"mac","scale":"2x","size":"128x128","filename":"icon_128x128@2x.png"},
    {"idiom":"mac","scale":"1x","size":"256x256","filename":"icon_256x256.png"},
    {"idiom":"mac","scale":"2x","size":"256x256","filename":"icon_256x256@2x.png"},
    {"idiom":"mac","scale":"1x","size":"512x512","filename":"icon_512x512.png"},
    {"idiom":"mac","scale":"2x","size":"512x512","filename":"icon_512x512@2x.png"}
  ],
  "info": {"author":"xcode","version":1}
}
JSON
echo '{"info":{"author":"xcode","version":1}}' > Nephele/Assets.xcassets/Contents.json
rm -rf "$TMP"
echo "App icon set written to $SET"
