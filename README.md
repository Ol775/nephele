# Nephele

A native macOS 26 app for managing a Cloudflare account: domains and DNS, alerts, usage, and (coming next) Workers, storage and Zero Trust. Pure Swift and SwiftUI. An independent project, not affiliated with Cloudflare.

Phase 1 (this release) covers sign-in with an API token, an overview, domains with full DNS management, alerts with notifications and a menu bar item, usage against Free plan allowances, Settings and a full Appearance screen.

## Privacy

- Your API token is stored in the macOS Keychain only. It is sent only to the Cloudflare API.
- No analytics, no telemetry, no server component. Results are cached in memory for about a minute and never written to disk.
- Anything destructive (deleting a DNS record, for example) asks you to confirm first, naming the target.

## Create an API token

In the Cloudflare dashboard go to Profile, API Tokens, Create Token. Start with read-only access:

- Zone: Zone Read, DNS Read
- Account: Notifications Read, Account Analytics Read, Account Settings Read

Add DNS Edit later if you want to change records. Missing permissions never break the app: the screens that need them show a prompt instead.

## Build

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
swift test --package-path Packages/CloudflareKit
xcodebuild test -scheme Nephele -destination 'platform=macOS'
```

To regenerate the app icon from `assets/logo.svg`:

```bash
./scripts/make-icons.sh
```

## Layout

- `Packages/CloudflareKit`: the typed Cloudflare API client, models, DNS validation and alert de-duplication (no UI).
- `Nephele`: the SwiftUI app, stores and screens.
- `docs/superpowers`: the design and the implementation plan.

## Known issues

- The icon is a concept master. A hand-tuned 16 px variant is still to do; check it in the Dock and menu bar before release.
- The D1 usage meters use `rowsRead` and `rowsWritten` from Cloudflare's GraphQL API, which have not been confirmed against a live account. If they fail, the other meters still show.
- The name and logo have not been legally cleared. Search the UK IPO and USPTO registers before any public release.

## Licence

MIT. See `LICENSE`.
