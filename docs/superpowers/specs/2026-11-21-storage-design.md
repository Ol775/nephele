# Nephele phase 2b: storage (KV, D1, R2) design

Date: 2026-11-21. Status: approved by the owner ("Yes then implement natively"); scope below is my proposal inside that go-ahead. Parent: `2026-11-21-cloudflare-mac-app-design.md`. Follows phase 2a (Workers).

## Intent
Browse and manage Workers KV, D1 and R2 from Nephele's new Storage screen (sidebar route `storage`, segmented KV / D1 / R2).

## Goals
- KV: namespaces (list, create, delete by typed name); keys (prefix filter, load more); view and edit a text value; delete key (confirmed).
- D1: databases (list, create, delete by typed name); a SQL console (single or multi-statement), results table, rows read/written and duration; table list; any statement that changes data or schema asks for confirmation naming the database.
- R2: buckets (list, create, delete by typed name); objects (prefix filter, load more, delete confirmed).
- Same safety and permission rules as Workers: reads work with read tokens, a forbidden write disables writes with a hint, no secret/value in logs.

## Non-goals
- R2 object upload/download and lifecycle, CORS, custom domains; KV bulk, expiry and metadata editing (existing metadata is shown only); D1 import/export/time travel; binary KV values (shown read-only as "binary, N bytes").

## Approaches
One `StorageStore` per product under a shared Storage screen vs three separate sidebar items. Chosen: one sidebar item with a segmented picker, one store per product (smaller sidebar, shared permission copy).

## Endpoints (verified in the OpenAPI spec 2026-11-21)
KV `/accounts/{id}/storage/kv/namespaces` (+`/{ns}/keys?prefix&cursor&limit`, `/{ns}/values/{key}` GET raw, PUT octet-stream, DELETE); D1 `/d1/database` (+`/{id}`, `POST /{id}/query {sql, params}` result `[{results, meta{rows_read, rows_written, duration}}]`); R2 `/r2/buckets` (result `{buckets:[{name, creation_date, location}]}`), `/r2/buckets/{b}/objects?prefix&cursor&per_page`, `DELETE .../objects/{key}`. Permissions: Workers KV Storage Read/Write, D1 Read/Write, Workers R2 Storage Read/Write.

## Left to the builder
Exact response models (fixtures from schemas, live shapes unconfirmed), pagination cursor field names (`result_info.cursor`), SQL statement classification (a simple keyword check on the first word of each statement).
