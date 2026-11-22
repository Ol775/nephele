# Features

Every screen, and which actions stop to ask first. "Typed name" means you must type the target's name to confirm.

## Overview
Requests, cache hit ratio, threats blocked and open alerts for the selected account, a requests chart (24 h, 7 d, 30 d), the alerts that need attention and your domains. Switch accounts in Settings.

## Domains and DNS
- Filter by name or show only domains that need attention. **⌘K** jumps to the filter.
- DNS records: A, AAAA, CNAME, TXT and MX, validated before they are sent (IPv4/IPv6 shape, hostnames, MX priority, proxied only where it applies).
- Edit a record, toggle proxying (**asks first**, with what changes) or delete (**asks first**).
- The domain's toolbar opens **Email**, **Firewall** and **Settings**.

## Per-domain settings
SSL/TLS encryption mode, Always use HTTPS, automatic HTTPS rewrites, minimum TLS version, TLS 1.3, security level and development mode. Changes that can take the site down (SSL off, Flexible or Strict; "I'm under attack"; minimum TLS 1.3) **explain the risk and ask first**. **Cache purge** by URL (up to 100) or everything (**typed domain name**).

## Firewall (WAF custom rules)
List, add, turn on or off and delete custom rules. Adding, turning on and deleting **ask first**; turning off does not. Rules that carry extra options (skip rules, custom responses, rate limits) are shown but cannot be toggled here, so nothing is silently dropped. Expressions use Cloudflare's rules language, for example `(ip.src eq 203.0.113.7)`.

## Email Routing
Forwarding rules from an address on your domain to a **verified** destination: add, turn on or off, delete (**asks first**). Catch-all and non-forwarding rules are listed but changed in the dashboard. Destination addresses are verified in the dashboard.

## Workers
Per-Worker settings and variables, write-only secrets, routes, custom domains, cron triggers, versions (deploy and rollback each **ask first**), a code editor that saves a new version (deploying it is a separate, confirmed step), live logs, and templates for new Workers. Deleting a Worker needs its **typed name**.

## Storage
- **KV:** namespaces, keys and text values; create, edit and delete.
- **D1:** databases and a SQL console. Anything that changes data **asks first**.
- **R2:** buckets and objects; delete only for now (**asks first**).

## Zero Trust
- **Tunnels:** list, create, delete (**typed name**). The connector token is never fetched or shown.
- **Applications:** list and delete (**typed name**). Editing stays in the dashboard because an update replaces the whole application.
- **Service tokens:** list, create, delete (**typed name**). The client secret is shown **once** with a Copy button, never stored.
- **Gateway:** list and delete rules (**typed name**).

## Turnstile
List widgets, create one (the secret key is shown **once**), delete (**typed name**).

## Pages
Projects and their deployments: retry, roll back and delete deployments (each **asks first**); delete a project (**typed name**). Creating projects and direct uploads stay in the dashboard.

## Alerts and usage
A poller checks Cloudflare's notification history and sends macOS notifications (choose which kinds, and how often, in Settings). A menu bar item shows open alerts. Usage compares Workers, KV, D1 and R2 against Free-plan allowances.

## Appearance
Light, dark or system; accent colour; density; corner radius; text size and typeface; icon weight; sidebar tint, icons-only mode, item order and visibility; which screen opens first; high contrast and reduce motion. Export and import your settings as JSON.

## Keyboard
**⌘K** search domains · **⌘,** Settings.
