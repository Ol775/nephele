# API token permissions

Nephele works with whatever your token allows. A screen whose permission is missing shows a prompt naming it instead of data, and **Settings → Account and API token** lists what was detected. Edit rights are not probed ahead of time: a control switches off the first time Cloudflare refuses a change.

Use the dashboard's names below (Profile → API Tokens → Create Custom Token).

| Area | Read (to browse) | Edit (to change) |
|---|---|---|
| Sign-in and overview | Zone: Zone Read · Account: Account Settings Read, Account Analytics Read | none |
| DNS | Zone: DNS Read | Zone: DNS Edit |
| Alerts | Account: Notifications Read | none (alerts are read and acknowledged locally) |
| Per-domain settings | Zone: Zone Settings Read | Zone Settings Edit; **Cache Purge** to purge |
| Firewall (WAF custom rules) | Zone: Zone WAF Read | Zone WAF Edit |
| Email Routing | Zone: Email Routing Rules Read · Account: Email Routing Addresses Read | Email Routing Rules Edit |
| Workers | Account: Workers Scripts Read (Workers Tail Read for live logs; Zone: Workers Routes Read for routes) | Workers Scripts Edit (and Workers Routes Edit) |
| Workers KV | Account: Workers KV Storage Read | Workers KV Storage Edit |
| D1 | Account: D1 Read | D1 Edit (the SQL console needs it to change data) |
| R2 | Account: Workers R2 Storage Read | Workers R2 Storage Edit |
| Tunnels | Account: Cloudflare Tunnel Read | Cloudflare Tunnel Edit |
| Access applications | Account: Access: Apps and Policies Read | Access: Apps and Policies Edit |
| Service tokens | Account: Access: Service Tokens Read | Access: Service Tokens Edit |
| Gateway rules | Account: Zero Trust Read | Zero Trust Edit |
| Turnstile | Account: Turnstile Sites Read | Turnstile Sites Edit |
| Pages | Account: Cloudflare Pages Read | Cloudflare Pages Edit |
| Usage meters | Account: Account Analytics Read | none |

Nephele never asks for more than it needs to show a screen, and it never uses a permission for anything other than the action you triggered.

## Create a token from the sign-in screen

Pick **Read only** or **Read and edit** on the sign-in screen, then **Create a … token**. Cloudflare opens with those permissions already ticked. Cloudflare's link format has no key for Notifications, Email Routing, WAF, Turnstile, Tunnels or Gateway, so add those by hand on that page if you want them.

## Tips

- Start read-only. Add an Edit permission when you first need it.
- Create a separate token per machine so you can revoke one without affecting the rest.
- Scope **Zone Resources** to the zones you manage with Nephele if you don't want it to see them all.
