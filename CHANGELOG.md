# Changelog

## Unreleased

## 0.1.3
- **Updates:** the saved token is read off the main thread, so after an update the window opens straight away and says it is waiting for the macOS Keychain prompt instead of appearing frozen with no window.

## 0.1.2
- **Sign-in:** a Full access level, and each level lists the permissions Cloudflare's link can't pre-tick.
- **Permissions:** Settings no longer claims "All present"; it says "No errors" and notes that an empty list can mean a missing permission. Empty Tunnels and Service tokens screens name the permission to check.

## 0.1.1
- **Sign-in:** choose Read only or Read and edit, and the Create a token link opens Cloudflare with those permissions already ticked.
- **Build:** Workers loading no longer relies on a newer Swift Result initialiser, so CI builds on the stock runner toolchain.

## 0.1.0 (beta)
First public release.

- **Overview, domains and DNS:** account overview with a requests chart, domain list, DNS records with validation and confirmation, proxy toggle.
- **Per-domain settings:** SSL/TLS mode, Always use HTTPS, HTTPS rewrites, minimum TLS, TLS 1.3, security level, development mode, cache purge by URL or everything. Risky changes explain themselves and ask first.
- **Firewall (WAF custom rules):** list, add, turn on or off, delete; confirmations; rules with options Nephele can't show are protected from lossy toggles.
- **Email Routing:** forwarding rules to verified destinations; add, turn on or off, delete.
- **Workers:** settings, variables, write-only secrets, routes, custom domains, cron triggers, versions with deploy and rollback, code editor, live logs, templates.
- **Storage:** Workers KV, D1 with a guarded SQL console, R2 buckets and objects.
- **Zero Trust:** tunnels, Access applications, service tokens (secret shown once), Gateway rules.
- **Turnstile:** list, create (secret shown once), delete.
- **Pages:** projects and deployments, retry, roll back, delete.
- **Alerts and usage:** notifications, menu bar item, usage against Free-plan allowances.
- **Appearance:** theme, accent, density, fonts, sidebar layout, settings export and import.
- **Signed in-app updates** from GitHub releases (Ed25519), with a Settings → Updates section and a **Check for Updates…** menu item.
- **Demo mode** (`--demo`) with built-in sample data.
- The app is no longer sandboxed (needed for the self-updater); it uses the hardened runtime.
