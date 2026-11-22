# Roadmap

Where Nephele is heading. Nothing here is a promise or a date; the order is a best guess and can change. Ideas and votes are welcome as [issues](https://github.com/Ol775/nephele/issues).

## Now: v0.1 beta

Shipped: overview, domains and DNS, per-domain settings and cache purge, WAF custom rules, Email Routing, Workers (code, versions, logs, secrets, triggers), KV, D1, R2, Zero Trust (tunnels, applications, service tokens, Gateway), Turnstile, Pages, alerts with notifications and a menu bar item, usage, appearance, signed in-app updates, a no-account demo mode.

## Next: from beta to 1.0

- **Live verification pass.** Exercise every write path (DNS, Workers, storage, Zero Trust, Pages, zone settings, WAF, Email, Turnstile, Gateway) against a real account and fix whatever the recorded fixtures got wrong. This is the gate for 1.0.
- **Accessibility audit.** A VoiceOver and keyboard walk-through of every screen, with fixes, then an `ACCESSIBILITY.md`.
- **Settings polish.** Show development mode's time remaining, preserve TLS 1.3's 0-RTT value, show values Nephele doesn't list instead of a blank picker.
- **Hand-tuned 16 px icon** and a check in the Dock and menu bar.
- **Busy and progress states** on the remaining controls (double-clicks, in-flight changes).

## Later

- **Email Routing:** catch-all, drop and Worker rules; destination address management.
- **WAF:** show and safely edit skip, rate-limit and custom-response rules; managed rules overview.
- **Gateway and Access:** edit rules and applications (needs a whole-object editor so nothing is dropped); policies.
- **Turnstile:** rotate secrets, edit widgets.
- **R2:** upload and download objects. **KV:** bulk import and export.
- **Workers:** metrics per Worker, tail filters.
- **DNS:** import and export zone files, bulk edits, record search across zones.
- **Global search** (jump to any domain, Worker, bucket or rule).
- **Localisation**, starting with the strings already in the UI.
- **Widgets** for alerts and usage.

## Needs a decision or outside help

- **Notarization.** Removes the first-launch "Open Anyway" step. Requires a paid Apple Developer ID.
- **Trademark and name clearance.** Search the UK IPO and USPTO registers for the name and logo before relying on them commercially.
- **Sandboxing.** The app is not sandboxed because the in-app updater has to replace the app bundle. A sandboxed build for the Mac App Store would need a different update path (and App Store review of a Cloudflare client).

## Not planned

- A Windows or Linux port. Nephele is a native macOS app.
- Anything that stores your token anywhere but the Keychain, or sends it anywhere but Cloudflare.
- Telemetry or accounts.

## Principles

- **Native and light.** SwiftUI and system frameworks, no third-party UI dependencies.
- **Safe by default.** Read-only until you add Edit permissions; the dangerous actions ask first.
- **Private.** No analytics, no accounts, no data collection.
- **Honest about what is verified.** Features are labelled beta until they have run against a live account.
