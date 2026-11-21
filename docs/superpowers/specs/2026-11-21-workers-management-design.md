# Nephele phase 2a: Workers management (design)

Date: 2026-11-21. Status: draft for approval. Parent spec: `2026-11-21-cloudflare-mac-app-design.md` ("Workers: full management"). Phase 2 is split into three plans: **2a Workers (this)**, 2b storage (KV, D1, R2), 2c Pages.

## Intent and why
Manage the owner's Workers from Nephele instead of the dashboard: see every Worker, change its settings, variables, secrets, routes and cron triggers, deploy new code, roll back, and watch live logs. The owner has not said which dashboard task annoys them most, so the build order below is my proposal.

## Goals
- Every Worker is browsable with a read-only token; every write needs an edit token and says so when it is missing.
- Deploys match how Cloudflare really works: saving creates a **version**, deploying is a separate step. The UI says "creates a new version" wherever it does.
- Every removal, rollback and delete names its target in a confirmation (type the Worker name to delete it).
- Secrets are write-only: set and delete, never displayed.

## Non-goals (this plan)
- Syntax-highlighting editor (Monaco). The editor is native and plain; swapping it later must not touch deploy logic.
- Multi-file / bundled projects, build steps, wrangler config import, TypeScript compile. The editor handles a single ES-module script (`main_module`); other modules in an existing Worker are listed read-only and re-sent unchanged on save.
- Workers for Platforms, preview deployments, Durable Object migrations, Queues, Workflows.
- Gradual rollouts UI: a deployment is 100% to one version. (The API allows splits; not built.)

## Anti-goals
- A save that silently drops a binding, secret or module the editor does not understand.
- A secret value reaching logs, the clipboard, or screen.
- Rollback or delete without a named confirmation.

## Constraints
- Reuse `CFClient` (`get`, `getAll`, `send`, retries), `LoadState`, the `PendingAction` confirm pattern from `DNSStore`, and `StubServer` TDD. Pure Swift, Swift 6.
- Token permissions (from the OpenAPI spec, checked 2026-11-21): read = Workers Scripts Read (Workers Tail Read also accepted); write = Workers Scripts Write; live tail = Workers Tail Read; routes = zone-level Workers Routes Read/Write; account settings reads need Account Settings Read. The Settings permission checklist gains rows for these.

## Approaches considered
Deploy model: (A) classic `PUT /scripts/{name}` whole-script overwrite; **(B, chosen by owner) Versions + Deployments**: `POST .../versions` (multipart: metadata + module files, `workers/message` annotation) then `POST .../deployments` (versions + percentage, `workers/message`). Rollback is a new deployment of an older version. A was rejected because it overwrites live code with no real history.
Editor: **(A, chosen by owner) native SwiftUI monospaced text view**; (B) WKWebView + Monaco rejected for now (bundled web asset, JS bridge, heaviest piece).

## Endpoints (verified in Cloudflare's OpenAPI spec 2026-11-21)
All under `/accounts/{id}/workers/scripts/{name}` unless noted.
- List scripts `GET /workers/scripts`; settings `GET/PATCH .../script-settings` (and `.../settings` for bindings/compat flags/observability); delete `DELETE .../{name}`.
- Code: `GET .../content/v2`. Versions: `GET/POST .../versions`, `GET .../versions/{id}`. Deployments: `GET/POST .../deployments`.
- Secrets: `GET/PUT .../secrets`, `DELETE .../secrets/{name}` (names only on read). Cron: `GET/PUT .../schedules`. workers.dev: `GET/POST/DELETE .../subdomain`; account subdomain `GET /workers/subdomain`.
- Custom domains: `GET/PUT/DELETE /workers/domains`. Routes (per zone): `/zones/{id}/workers/routes` list/create/replace/delete.
- Live tail: `POST .../tails` (start) and `DELETE .../tails/{id}`. The start response carries `id`, `url` (the WebSocket) and `expires_at` (confirmed in the spec 2026-11-21); the socket handshake itself is unverified live. Real-time logs may sample under load and allow at most 10 viewers per Worker.

## Parts and build order
1. **Kit layer + list/overview:** models, `workers()` list, per-Worker overview (usage from existing analytics, latest deployment, triggers summary). Sidebar "Workers" route.
2. **Settings, variables, secrets:** compatibility date, `nodejs_compat`, observability, workers.dev toggle; plain variables add/edit/remove; secrets set/delete (value field cleared after send, never stored).
3. **Routes, custom domains, cron triggers:** validation (route pattern needs a zone host; cron has 5 fields), confirm on removal.
4. **Versions, deploy, rollback:** version list with message and date, deployment list, "deploy this version" and rollback, each confirmed naming version and Worker.
5. **Code editor:** load current `main_module`, edit, "Save as new version" (message required), then separate "Deploy". Unsaved-change guard. Bindings and non-edited modules are carried through unchanged.
6. **Live log tail:** start/stop, errors-only filter, line cap in memory, handles sampling warning and the 10-viewer limit with a clear message.
7. **Create from template and delete Worker:** hello, HTTP API, scheduled job templates; delete requires typing the Worker name.

## Review focus (inputs the spec implies but tests must pin)
- Worker with many bindings/modules: save must not drop any (round-trip test).
- Token without write scope: write controls disabled with explanation, no failed requests.
- Name collisions, invalid names (lowercase letters, digits, hyphens), invalid cron and route patterns rejected before any request.
- Secret values never appear in errors, logs, or view state after send.
- Rate limiting and partial failure when loading overview (some panels forbidden, others load).

## Left to the builder
- Exact multipart construction, model shapes, and how settings/bindings merge on PATCH (verify with fixtures from real response shapes; scrub account data).
- Navigation inside a Worker (tabs vs sections), editor font/size via existing Appearance tokens.
- Tail transport details once the start response is confirmed.

## My calls (not yet agreed)
- Order of parts 1 to 7 (proposal pending the owner's pain points).
- Single-module editor scope; deployments always 100% to one version.
- Templates limited to three.
