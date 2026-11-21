# Nephele: a native Mac app for managing Cloudflare (design)

Name and logo: "Nephele" (Greek cloud goddess) with the "Cloud cleft" mark (an ivory cloud split by a rising seam, on an orange tile) designed with Codex, in `assets/logo.svg`; four alternatives and notes are in `assets/logo-concepts/`. It avoids "Cloudflare" and "flare" and is not Cloudflare's flat-bottomed two-bump cloud, but the cloud and lightning area is crowded, so compare it with existing logos before public release. Still to do: a 16 px optical variant and a packaged macOS icon set. Not legally cleared. A web search found a NEPHELE registration owned by Hypersecu Information Systems (Class 45 per one source) and a cloud software-licensing service also called Nephele. Run a UK IPO and USPTO search in classes 9, 42 and 45 before any public release, and be ready to rename.

Search findings (2026-11-21, aggregator sites only, not official registers): NEPHELE reg. 5956750 (Hypersecu Information Systems) covers authentication services (one-time passwords, WebAuthn, PKI, single sign-on), which sits near our Zero Trust screens. Two other US NEPHELE filings are pending with no goods visible (Xiamen Shuba serial 90151364; Angelik Pathway "NEPHELE LUXE" serial 98435634). An EU research project named NEPHELE (cloud-edge continuum, on Eclipse GitLab) and a licensing service use the name. No UK IPO record found, which is inconclusive. No Nephele app found on the App Store or Homebrew. Verdict: moderate risk; fine for private beta, not cleared for public.

Date: 2026-11-21. Status: draft for approval.

## Intent and why
A native macOS 26+ app that manages a Cloudflare account the way the dashboard does: overview of every domain, alerts, usage, domain/DNS management, developer platform and storage, Zero Trust. Owner is a solo developer/homelab user with a busy personal account (many Workers, R2, D1, Access apps, Tunnels, WAF rules). Private beta for the owner only, then a public GitHub release.

The owner has not yet said what is slowest or most annoying in the dashboard today. Phase 1 contents below are therefore my proposal, to be reordered once they say.

## Goals
- Native feel: SwiftUI, macOS 26 (Liquid Glass), sidebar navigation, menu bar item for quick domain/DNS and alert status.
- Read-first: every area is browsable before it is editable.
- Safe writes: any destructive or hard-to-reverse change (delete record, purge cache, delete bucket/Worker) needs an explicit confirmation naming the target.
- Public-repo ready from day one: no secrets, no personal identifiers in code, history, screenshots; MIT licence; GitHub handle only (Ol775).

## Non-goals (for now)
- Rust, FFI, or any helper process. Decided: pure Swift.
- OAuth / multi-user / multi-account. Beta is single-owner, API token.
- Billing and plan changes.
- Windows/Linux/iOS.
- Full dashboard parity in one go. Phased below.

## Anti-goals (failure even if it works)
- Feels like a web wrapper or Electron-style app.
- A token or account data leaking into logs, crash reports, the repo or screenshots.
- A click that silently destroys production config.

## Constraints
- macOS 26+, Swift 6, SwiftUI. Swift Package Manager.
- Cloudflare API is HTTPS/JSON (REST v4 plus GraphQL Analytics). Rate limits apply (about 1200 requests per 5 minutes per token); client must back off and cache.
- API token is stored in the Keychain only. Token scopes decide what each area can show; the UI must degrade gracefully (clear "token lacks permission X" state, not an error wall).

## Approaches considered
1. Rust core + UniFFI Swift bindings. Rejected: the work is network-bound, so Rust's speed is unused; adds FFI, two toolchains, and a bridge for errors/async.
2. Rust helper process over localhost. Rejected: process lifecycle, local port, extra signing, same lack of benefit.
3. **Pure Swift (chosen by owner).** One toolchain, URLSession + async/await + Codable, Keychain and notifications native. Cloudflare API code lives in its own Swift package (`CloudflareKit`), so a future reuse or swap stays possible.

## Architecture
- `CloudflareKit` (Swift package, no UI): typed client for the API areas in scope, pagination, rate-limit backoff, GraphQL analytics queries, typed errors (auth, permission, rate-limit, API error with Cloudflare's code/message). Models hand-written or generated from Cloudflare's OpenAPI schema (builder's call, see below).
- App target: SwiftUI views, one observable store per area (Domains, DNS, Alerts, Usage, ...) holding cached results and refresh state. Keychain wrapper for the token.
- Background refresh (alerts, status) via a timer while running; notifications via UserNotifications. No server component.
- Tests: `CloudflareKit` unit-tested against recorded JSON fixtures (fixtures scrubbed of real account IDs and names); no live-API tests in CI.

## Phasing
1. **Foundation + Overview:** token entry/validation/Keychain, zone list with status, plan, nameservers, quick health. DNS records (list, add, edit, delete with confirm). Alerts (notification policies and history). Usage (analytics per zone, account-level Workers/R2/D1/KV usage vs plan allowances).
2. **Developer platform and storage:** Workers managed in full (see below), Pages, R2 buckets/objects, D1 databases (browse, run query), KV namespaces.
3. **Zero Trust:** Access applications and policies, Tunnels (status), Gateway basics.
4. **Everything else:** WAF/rules, SSL/TLS, caching, email routing, Turnstile, and so on, chosen by actual use.

Each phase ships as something runnable and usable before the next starts.

## Workers: full management (phase 2)
Per Worker: overview metrics; code editor with save-and-deploy and a version message; bindings (KV, D1, R2, service) add/remove; variables (plain) and secrets (write-only, never displayed); routes, custom domains and cron triggers with validation; version history with roll back; live log tail with errors-only filter; settings (compatibility date, nodejs_compat, observability, workers.dev toggle) and delete (type the name to confirm). Creating a Worker from templates (hello, HTTP API, scheduled job). Every removal, rollback and delete asks for confirmation naming the target. Changes that create a new version say so.

## App Settings (separate from Appearance)
API token (Keychain; verify, replace, remove) with a permission checklist that explains which screens need which permission; notification categories and polling interval; open at login and menu bar item; local cache clear; keyboard shortcuts; about. No analytics: the app talks only to the Cloudflare API.

## Look and personalisation
Interactive mockup (artifact, v5) is the visual reference: operator-dashboard layout, one accent (Cloudflare orange default), warm neutrals, status as dots, area charts, real line icons, empty/loading/error states. Appearance screen lets the user choose light/dark/system, accent (presets plus custom, with automatic readable text colour), tinted sidebar, corner radius, icon weight, typeface, text size, density, sidebar side and style, launch screen, sidebar item visibility/order, Overview sections, increased contrast and reduced motion, with settings export/import. In the SwiftUI app these become design tokens plus an `@AppStorage`-backed settings model; the macOS 26 Liquid Glass material replaces the mockup's flat tint.

## Decided by owner
- Pure Swift; SwiftUI; macOS 26+.
- Single owner for beta, then public GitHub.
- API-token auth for now.

## My calls (not yet agreed)
- Sidebar layout and menu bar item described above.
- Phase order above (proposal, pending the owner's dashboard pain points).
- Working name CFManager; a public name should avoid implying it is an official Cloudflare product.

## Left to the builder
- Hand-written models vs `swift-openapi-generator` from Cloudflare's schema (try the generator first; fall back if the schema is too large or loose).
- Exact caching/refresh intervals, view design details, navigation structure inside each area.
- Distribution for public release (notarised DMG vs Homebrew cask), set up before the public flip.

## Decided later in the conversation
- Name: Nephele, kept by the owner after the trademark check above (private beta now, re-check before public).
- Workers fully manageable and a dedicated Settings page are in scope.

## Open items
- Owner's top dashboard pain points (reorders phase 1).
- Whether beta uses a dedicated, scoped token (recommended: read-only first, a separate write token later).
