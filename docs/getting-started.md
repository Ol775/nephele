# Getting started

## Requirements

- macOS 26 (Tahoe) or later, Apple silicon or Intel.
- A Cloudflare account and an API token (below).

## Install

Pick one:

1. **DMG.** Download `Nephele-x.y.z.dmg` from the [latest release](https://github.com/Ol775/nephele/releases/latest), open it and drag **Nephele** onto **Applications**.
2. **Homebrew.** `brew install --cask Ol775/tap/nephele`
3. **Build it yourself.** See [CONTRIBUTING.md](../CONTRIBUTING.md#building).

### First launch (DMG only)

Nephele is signed ad hoc rather than notarized, so macOS blocks a downloaded copy the first time:

1. Open Nephele. macOS says it can't verify the app. Click **Done**.
2. Open **System Settings → Privacy & Security**, scroll to **Security** and click **Open Anyway** next to Nephele. Confirm with your password.

Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Nephele.app`

Homebrew's cask and in-app updates clear the flag for you.

## Create an API token

1. Sign in to the Cloudflare dashboard and open **My Profile → API Tokens → Create Token → Create Custom Token**.
2. Give it a name such as "Nephele (read-only)".
3. Add the permissions from the **Read** column of [permissions.md](permissions.md). Start with these:
   - Zone: **Zone Read**, **DNS Read**
   - Account: **Notifications Read**, **Account Analytics Read**, **Account Settings Read**
4. Set **Zone Resources** to *All zones* (or the zones you want) and **Account Resources** to your account.
5. Create the token and copy it. Cloudflare shows it once.

Nephele accepts both user tokens (`cfut_…`) and account-owned tokens (`cfat_…`).

## Sign in

Paste the token into Nephele. It checks the token, finds your accounts and shows which permissions are present. The token is saved in the macOS Keychain; Nephele never writes it anywhere else.

## Making changes

Add the matching **Edit** permissions to the token only for the areas you want to change. Until then, the controls in that area are switched off with a note saying which permission to add. You can edit the token in Cloudflare without re-pasting it into Nephele.

## Try it without an account

```sh
/Applications/Nephele.app/Contents/MacOS/Nephele --demo
```

Demo mode answers every request locally with sample data (fictional `.example` domains). It uses its own throwaway settings, never touches the Keychain, and never contacts Cloudflare or GitHub. Actions "succeed" without doing anything.

## Updating

Nephele checks for updates at launch. Turn that off, or check by hand, in **Settings → Updates** (or **Nephele → Check for Updates…**). With Homebrew you can also run `brew upgrade --cask nephele`.

## Uninstall

Quit Nephele and delete it from Applications. To remove its data too:

```sh
defaults delete io.github.ol775.nephele
rm -rf ~/Library/Caches/Nephele-updates
security delete-generic-password -s io.github.ol775.nephele
```

The last line removes your API token from the Keychain. The token itself stays valid in Cloudflare: revoke it there if you no longer need it.
