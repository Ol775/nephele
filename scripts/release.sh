#!/bin/zsh
# Publishes the version in project.yml: builds the universal DMG, signs it with the offline release key, creates the
# GitHub release (DMG + .sha256 + .sig2) and updates the Homebrew cask in Ol775/homebrew-tap.
# Run after bumping the version (scripts/bump.sh), updating CHANGELOG.md and pushing main.
# Usage: scripts/release.sh "short release note"      (set DRY_RUN=1 to build and sign without publishing)
# The signing key (never committed, back it up!) lives at ~/.config/nephele/signing.key; its public half is Updater.publicKey.
set -e
cd "$(dirname "$0")/.."
note="${1:?usage: scripts/release.sh \"short release note\"}"
ver=$(grep -o 'MARKETING_VERSION: "[^"]*"' project.yml | cut -d'"' -f2)
key="${SIGNING_KEY:-$HOME/.config/nephele/signing.key}"
[ -f "$key" ] || { echo "No signing key at $key. Releases must be signed (see tools/sign-tool.swift)."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
git fetch -q origin main; [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Push main first."; exit 1; }
mkdir -p build && swiftc -O tools/sign-tool.swift -o build/sign-tool 2>/dev/null
[ "$(build/sign-tool public "$key")" = "$(grep -o 'publicKey = "[^"]*"' Nephele/Updates/Updater.swift | cut -d'"' -f2)" ] || { echo "The signing key doesn't match the public key built into the app."; exit 1; }
scripts/build-dmg.sh >/dev/null
dmg="dist/Nephele-$ver.dmg"
build/sign-tool sign-update "$key" "$dmg" "$ver" > "$dmg.sig2"
if [ -n "$DRY_RUN" ]; then echo "Dry run: built and signed $dmg"; exit 0; fi
gh release create "v$ver" "$dmg" "$dmg.sha256" "$dmg.sig2" --repo Ol775/nephele --title "v$ver" --notes "$note" --latest
tap="${TAP_DIR:-build/homebrew-tap}"
[ -d "$tap/.git" ] || git clone -q https://github.com/Ol775/homebrew-tap "$tap"
git -C "$tap" pull -q --ff-only origin main
sha=$(cut -d' ' -f1 "$dmg.sha256")
if [ ! -f "$tap/Casks/nephele.rb" ]; then
  cat > "$tap/Casks/nephele.rb" <<CASK
cask "nephele" do
  version "$ver"
  sha256 "$sha"

  url "https://github.com/Ol775/nephele/releases/download/v#{version}/Nephele-#{version}.dmg"
  name "Nephele"
  desc "Native Mac app for managing a Cloudflare account"
  homepage "https://github.com/Ol775/nephele"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "Nephele.app"

  # Ad-hoc signed (no paid Apple Developer ID): clear the quarantine flag to skip the Gatekeeper prompt.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Nephele.app"]
  end

  zap trash: [
    "~/Library/Caches/Nephele-updates",
    "~/Library/Preferences/io.github.ol775.nephele.plist",
    "~/Library/Saved Application State/io.github.ol775.nephele.savedState",
  ]
end
CASK
else
  sed -i '' -e "s/^  version \".*\"/  version \"$ver\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$tap/Casks/nephele.rb"
fi
git -C "$tap" add -A && git -C "$tap" commit -q -m "nephele $ver" && git -C "$tap" push -q origin main && echo "Homebrew tap updated to $ver"
echo "Released v$ver"
