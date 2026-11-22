# Privacy

**Short version:** Nephele talks only to Cloudflare (to do what you ask) and GitHub (to check for updates). There are no Nephele servers, accounts, analytics or telemetry, and nothing about you is collected.

## What the app reads
Whatever your API token allows, only when a screen needs it: your accounts, domains and DNS records, Workers, KV/D1/R2 data you open, Zero Trust objects, Pages projects, alerts, usage numbers and so on. This data is shown in the window and held in memory for about a minute. It is not written to disk.

## What is stored
- **Your API token**, in the macOS Keychain (service `io.github.ol775.nephele`).
- **Your settings** (theme, accent, layout, notification choices, update preference) and **which alerts you have already seen**, in the app's standard preferences for `io.github.ol775.nephele`.

Secrets Cloudflare returns once (service tokens, Turnstile secrets) are shown on screen and then dropped; Nephele does not store them.

## Network requests
1. `api.cloudflare.com`: every action you take. The token is sent only here.
2. `api.github.com` and `github.com`: the update check at launch (switch it off in Settings → Updates) and, when you choose **Update now**, the release download. GitHub sees your IP address as it would for any web request.

Nothing else. `--demo` mode makes no requests at all.

## Deleting your data
Quit Nephele, then:

```sh
defaults delete io.github.ol775.nephele
rm -rf ~/Library/Caches/Nephele-updates
security delete-generic-password -s io.github.ol775.nephele
```

The token also stays valid in Cloudflare until you revoke it there.
