# Nephele phase 3: Zero Trust (design and plan)

> For agentic workers: execute with superpowers:executing-plans (native, inline). Spec and plan are combined because the owner asked to plan and implement in one go ("Plan phase 3 and implement using native").

**Goal:** Manage Tunnels, Access applications and Access service tokens from Nephele.
**Architecture:** Kit `ZeroTrust.swift` (models + `CFClient` extension) → app `ZeroTrustStore` (tunnels, apps, tokens sub-stores, same patterns as `R2Store`) → `ZeroTrustView` with a segmented picker. Route `.zeroTrust`.
**Spec:** this file. Parent: `2026-11-21-cloudflare-mac-app-design.md`.

## Scope (my calls, not yet agreed)
- **Tunnels:** list with status, view connections (colo, origin IP), create (remotely managed, `config_src: cloudflare`), delete (typed name). The run token is never fetched or shown (anti-goal: a secret reaching the screen).
- **Access apps:** list (name, domain, type, session duration, policy count), delete (typed name). Read-only otherwise: `PUT` replaces the whole app, so editing risks dropping fields; create has a polymorphic body.
- **Service tokens:** list (name, client id, expiry), create (name + duration), delete (typed name). The client secret is returned once at creation: shown once in a sheet with Copy, never stored in state after dismissal, never logged.
- Non-goals: policies editing, Gateway rules, WARP/devices, tunnel ingress editing, rotate.

## Verified (OpenAPI 2026-11-22)
- `/accounts/{id}/cfd_tunnel` GET (filters `is_deleted`, `status`, `per_page`, `page`) and POST `{name, config_src, tunnel_secret?}`; `/cfd_tunnel/{id}` DELETE; `/cfd_tunnel/{id}/connections` GET. Read = Cloudflare Tunnel Read, write = Cloudflare Tunnel Write.
- `/accounts/{id}/access/apps` GET (page/per_page) and `/access/apps/{id}` DELETE. Read = Access: Apps and Policies Read, write = ... Write.
- `/accounts/{id}/access/service_tokens` GET/POST `{name, duration}`; `/{id}` DELETE. Read = Access: Service Tokens Read, write = ... Write.
- Live response shapes are unconfirmed; decoding is tolerant (all fields except id/name optional).

## Global constraints
Swift 6, TDD with StubServer, path segments via `pathSegment`, per-feature `canWrite`, identityEpoch guards, typed-name deletes, no secret in errors/logs.

## Review focus
1. Service-token secret: shown once, absent from store state after dismissal and from error text.
2. Deleting an active tunnel: API error shown, list unchanged.
3. Account switch mid-create/delete: late result ignored.
4. Read-only token: write controls disabled with explanation.
5. Unknown/missing fields in live responses don't fail the whole list.

## Tasks
1. **Kit `ZeroTrust.swift`** (tests `ZeroTrustTests`): `Tunnel`, `TunnelConnection`, `AccessApp`, `ServiceToken`, `CreatedServiceToken`; `tunnels`, `tunnelConnections`, `createTunnel`, `deleteTunnel`, `accessApps`, `deleteAccessApp`, `serviceTokens`, `createServiceToken`, `deleteServiceToken`; `validTunnelName`.
2. **App `ZeroTrustStore`** (tests `ZeroTrustStoreTests`): three sub-stores, confirm via typed name, one-shot secret handoff.
3. **Views + route + docs** (`ViewSmokeTests` render, README, Settings permission copy).
4. Fresh Opus review, one fix pass.
