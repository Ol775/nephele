# Architecture

```
Packages/CloudflareKit   typed Cloudflare API client, models, validation (no UI)
  Sources/CloudflareKit        CFClient actor + one file per API area
  Sources/CloudflareKitTesting StubServer and URLProtocol helpers for tests
Nephele/                 the SwiftUI app
  Session/ Auth/               sign-in, accounts, token in the Keychain
  Storage/ Domains/ ...        @Observable stores, one per area
  Views/                       SwiftUI screens
  Shared/                      LoadState, ConfirmGate, guarded writes
  Updates/                     signed GitHub updater
  Demo/                        --demo sample data and screenshot helper
docs/                    guides; docs/superpowers holds the design specs and plans
tools/                   sign-tool (release signing), render-svg (icon)
scripts/                 icons, DMG and release scripts
```

## Principles

- **Typed and tolerant.** Models decode only what the app uses and ignore the rest, so a new field in Cloudflare's response never breaks a screen.
- **One client.** `CFClient` handles auth, pagination, rate-limit backoff, the response envelope and typed errors (unauthorized, permission denied, rate limited, API error). Tokens never appear in errors or logs.
- **Stores own state.** Each area has an `@Observable @MainActor` store with a `LoadState`, per-area `canWrite` flags that flip off on a forbidden response, and an `identityEpoch` guard so a late response from a previous account is dropped.
- **Confirm the dangerous things.** `ConfirmGate` makes a confirmation single-use; `TypedConfirmSheet` requires the exact name for destructive actions.
- **Secrets are one-shot.** Secrets returned once by Cloudflare travel in types that hide them from descriptions and mirrors and are dropped after display.
- **Test with stubs.** Swift Testing plus `StubServer` (a `URLProtocol`) exercises every store and client call without a network.

## Tests

```sh
swift test --package-path Packages/CloudflareKit
xcodebuild test -scheme Nephele -destination 'platform=macOS'
```

The design documents and per-feature plans in `docs/superpowers` explain why each area is shaped the way it is.
