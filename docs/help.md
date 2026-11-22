# Help and troubleshooting

## macOS won't open Nephele ("can't be verified")
Nephele is signed ad hoc, not notarized. Open **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Nephele.app`. The Homebrew cask does this for you.

## "That doesn't look like a Cloudflare API token"
Paste the token itself, not its name or ID. New tokens start `cfut_` (user) or `cfat_` (account-owned); older ones are 40 letters and numbers. Make sure no spaces or line breaks were added.

## "This token can't see any account"
Add **Account: Account Settings Read** to the token.

## A screen asks me to add a permission
That screen needs a permission your token lacks. Open the token in Cloudflare, add the permission named on the screen ([permissions.md](permissions.md)), save, then press **Refresh** or reopen the screen. You don't need to re-paste the token.

## A control is greyed out with a lock icon
Cloudflare refused a change because the token has no Edit permission for it. Add it and try again. To re-check, reopen the screen (per-domain screens) or restart Nephele.

## Changes don't show up in the dashboard
Nephele shows Cloudflare's answer. If a change failed, the error appears above the form. Some changes (cache purge, SSL) take a few seconds to take effect.

## "Cloudflare is limiting requests"
You hit the API rate limit. Wait a minute. Nephele backs off automatically and caches results for about a minute.

## I was signed out
Cloudflare rejected the token (revoked, expired or deleted). Create a new token and paste it.

## macOS asks to allow Keychain access after an update
Choose **Always Allow**. Ad-hoc signed apps get a new code identity with each update, so macOS asks again once.

## Updates fail with "isn't signed" or "signature didn't check out"
Nephele only installs releases signed with the project's key. If you see this, don't install manually from an unknown source: download from the [releases page](https://github.com/Ol775/nephele/releases) and compare the file's checksum (`shasum -a 256 Nephele-x.y.z.dmg`) with the `.sha256` asset.

## "Nephele can't replace itself here"
Move Nephele to **Applications** (not a disk image or a read-only folder) and try again.

## Notifications don't appear
Allow Nephele in **System Settings → Notifications**, and check that the kinds you want are on in **Settings → Notifications**.

## The menu bar item is missing
Turn it on in **Settings → General → Show the menu bar item**. If you use a menu bar manager, it may be hiding new items.

## Report a problem
Open an [issue](https://github.com/Ol775/nephele/issues/new/choose). Include your macOS and Nephele versions and what you did, but **never paste an API token**. For security problems use the private route in [SECURITY.md](../SECURITY.md).
