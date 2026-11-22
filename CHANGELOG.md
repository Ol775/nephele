# Changelog

## Unreleased

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
