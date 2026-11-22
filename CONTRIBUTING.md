# Contributing

Thanks for helping. Bug reports, ideas and pull requests are welcome.

## Reporting bugs and ideas
Use [Issues](https://github.com/Ol775/nephele/issues/new/choose). Never paste an API token or screenshots showing real account data. For security problems use the private route in [SECURITY.md](SECURITY.md).

## Building
Requirements: macOS 26, Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate                                  # regenerate after adding or removing files
swift test --package-path Packages/CloudflareKit   # the API client
xcodebuild test -scheme Nephele -destination 'platform=macOS'   # the app
```

The updater has an opt-in live test that downloads the published release and verifies it: `TEST_RUNNER_NEPHELE_LIVE_UPDATE_TEST=1 xcodebuild test -scheme Nephele -destination 'platform=macOS' -only-testing:NepheleTests/LiveUpdaterTests`.

Run the app with sample data and no account: build it, then `Nephele.app/Contents/MacOS/Nephele --demo`.

## Pull requests
- Keep each PR small and focused, and say what you checked.
- **Tests first.** New API calls get a client test (path, verb, body) and new behaviour in a store gets a store test, using `StubServer`. See `Packages/CloudflareKit/Tests` and `NepheleTests`.
- **Safe by default.** Destructive or site-affecting actions must confirm (`ConfirmGate`, or `TypedConfirmSheet` for deletes). Secrets must never reach logs, errors or descriptions. A write that replaces a whole object must send everything or refuse.
- **Permissions.** New screens must degrade gracefully when the token lacks a permission, and name it. Update [docs/permissions.md](docs/permissions.md) and the Settings copy.
- **Native and light.** SwiftUI and system frameworks only; no new dependencies without discussion.
- **No telemetry** and no network requests other than Cloudflare's API and the update check.
- **Accessibility.** Icon-only controls need an accessibility label; everything must work from the keyboard.
- Screenshots in the repo must come from `--demo` (sample data), never a real account.
- Changes to the updater (`Nephele/Updates/Updater.swift`) need extra care: explain how the trust model in [SECURITY.md](SECURITY.md) still holds.
- Add a line to [CHANGELOG.md](CHANGELOG.md) under "Unreleased".

## Regenerating screenshots and GIFs
```sh
Nephele --demo --theme=light --snapshot=/tmp/shots       # PNG of every screen
Nephele --demo --accent="#2F6FED" --only=overview --snapshot=/tmp/shots-blue
```
`--only=a,b` limits which screens are captured; `--route=`, `--theme=` and `--accent=` set up the demo. The README GIFs are assembled from these PNGs with `ffmpeg`.

## Releasing (maintainer)
`scripts/release.sh "notes"` builds a universal app, packs and signs the DMG with the offline release key, and publishes the GitHub release. See the header of that script.

## Ideas
Look at [ROADMAP.md](ROADMAP.md) first. Items under "Needs a decision or outside help" are where input matters most.
