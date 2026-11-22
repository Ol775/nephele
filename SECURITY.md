# Security

## Reporting a vulnerability
Please use GitHub's **private vulnerability reporting** (Security tab → *Report a vulnerability*) rather than a public issue. You will get a reply within a few days. Please never include a real API token in a report.

## What the app does
- Signs in with a Cloudflare API token you paste. The token is stored in the **macOS Keychain** (service `io.github.ol775.nephele`) and sent only to `https://api.cloudflare.com/`.
- Calls the Cloudflare API to read your account and, only when you ask, to change it. Nothing is cached on disk: results live in memory for about a minute. Saved on disk are only your appearance settings and which alerts you have seen.
- Checks `api.github.com` and downloads from `github.com` for updates (see below). You can turn the check off in Settings.
- No telemetry, no analytics, no accounts, no third-party SDKs.
- **Demo mode** (`--demo`) answers every request locally and never touches the network or the Keychain.

## Safeguards for your Cloudflare account
- **Least privilege.** Start with a read-only token. Missing Edit permissions switch the controls off rather than failing silently. [docs/permissions.md](docs/permissions.md) lists exactly what each screen needs.
- **Confirmations.** Deletes name their target; destructive or high-impact actions (Workers, buckets, Pages projects, tunnels, Access applications, service tokens, Turnstile widgets, Gateway rules, purge everything) require typing the name. Changes that can take a site down (SSL mode, "I'm under attack", WAF rules, minimum TLS 1.3) explain the risk first. Confirmations are single-use.
- **Secrets.** Worker secrets are write-only. Service-token and Turnstile secrets are shown once, never stored, and kept out of logs, errors and debug descriptions. Tunnel connector tokens are never fetched.
- **No silent data loss.** Operations that replace a whole object on Cloudflare's side (WAF rule toggles, Email Routing, Workers uploads) re-send everything or refuse when the model can't represent it; creating the first WAF rule re-reads the ruleset first so existing rules are never overwritten.
- **Account switches.** A response that arrives after you switch accounts is discarded.
- **403 handling.** A permission error locks a control only when Cloudflare's message is about the token; plan limits and other refusals show their own message.

## App sandbox
Nephele is **not sandboxed**. The in-app updater has to replace the app bundle and launch a small helper script, which the sandbox forbids. It is built with the **hardened runtime** and is signed ad hoc (it is **not notarized**: that needs a paid Apple Developer ID). A process running as your own user can already read your files, so same-user attacks are out of scope.

## Updates
Updates come only from this repository's GitHub releases and install only if **all** of these pass:

1. The asset URL is exactly `https://github.com/Ol775/nephele/releases/download/…` (no port, credentials, query, `..` or empty path segments), and every redirect stays on `github.com` or `*.githubusercontent.com`.
2. The release version is plain `x.y.z` and newer than the installed one.
3. An **Ed25519 signature**, made offline with a private key that never leaves the maintainer's Mac and is never committed, verifies over `"nephele-update\nv<version>\n"` plus the disk image bytes. The public key is built into the app (`Updater.publicKey`), so a hijacked GitHub account or release cannot push an update that installs, and an older signed image cannot be passed off as a newer one.
4. The SHA-256 matches, checked again right before mounting.
5. The app inside has bundle id `io.github.ol775.nephele`, the announced version and a valid code signature.
6. The executable's fingerprint, taken at verification, is unchanged at install time.

Downloads are capped at 100 MB and 10 minutes. After the swap the installed app is verified again and the previous version is restored if it fails. If the signing key is ever lost or leaked, a new release with a new key must be installed manually.

## Verifying a release yourself
```sh
shasum -a 256 Nephele-X.Y.Z.dmg   # compare with the .sha256 asset
```
The signature asset is `Nephele-X.Y.Z.dmg.sig2` (base64 Ed25519). The public key is `Updater.publicKey` in `Nephele/Updates/Updater.swift`.

## Review history
Each feature area was reviewed during development by an AI-assisted code review plus an automated security review, and the findings were fixed with tests (see the commit history). **There has been no independent security audit.** Reviewers and researchers are welcome.

## Supported versions
Only the latest release receives fixes.
