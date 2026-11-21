# Nephele Storage (Phase 2b) Implementation Plan

> Executed inline (owner chose native). Spec: `docs/superpowers/specs/2026-11-21-storage-design.md`.

**Goal:** KV, D1 and R2 management on one Storage screen. **Stack:** as phase 2a (CloudflareKit calls via `CFClient.get/raw/download`, `LoadState`, `ConfirmGate`, `StubServer`).

## Global Constraints
Same as the Workers plan: Swift 6, no new dependencies, TDD, named confirmations, typed-name delete for namespaces/databases/buckets, secrets/values never logged, write-denied flips a `canWrite` flag with a hint, account pinned per store, fixtures from OpenAPI schemas.

## Review Focus
- A forbidden write disables writes without failing reads; stale loads after an account switch are dropped (epoch guard).
- D1 statements that change data never run without confirmation; read-only `SELECT/PRAGMA/EXPLAIN` run directly; multi-statement input is classified by its most destructive statement.
- Pagination cursors: "Load more" appends without duplicating; changing the prefix resets.
- KV value that is not UTF-8 is never written back.

### Task 1: KV (Kit + store + view + Storage route)
Kit `KV.swift`: `KVNamespace {id,title}`, `KVKey {name, expiration: Int?}`, `kvNamespaces`, `createKVNamespace(title)`, `deleteKVNamespace`, `kvKeys(namespace:prefix:cursor:limit:) -> (keys, nextCursor)`, `kvValue -> Data`, `putKVValue(Data)`, `deleteKVKey`. App: `.storage` route, `StorageStore` (KV part), `StorageView` with picker, KV view. Tests: Kit decode/paths/bodies; app load, pagination, edit, delete confirm, forbidden write, binary read-only.

### Task 2: D1
Kit `D1.swift`: `D1Database {uuid,name,fileSize?,numTables?}`, `d1Databases`, `createD1Database(name)`, `deleteD1Database`, `queryD1(databaseID:sql:) -> [D1Result]` (`columns`, `rows: [[String]]`, `rowsRead`, `rowsWritten`, `duration`), `D1Statement.isReadOnly(_ sql)`. App: D1 section of the store, SQL console view with confirm for writes. Tests: classification (`SELECT`, `WITH`, `PRAGMA`, `EXPLAIN` read-only; `DROP/DELETE/UPDATE/INSERT/ALTER/CREATE/REPLACE` not; multi-statement takes the worst), decode, confirm-before-write, forbidden write.

### Task 3: R2 + wiring + docs
Kit `R2.swift`: `R2Bucket {name, creationDate?, location?}`, `r2Buckets`, `createR2Bucket`, `deleteR2Bucket`, `r2Objects(bucket:prefix:cursor:) -> (objects, nextCursor)`, `deleteR2Object`. App: R2 section, view; Settings permission copy, README. Tests as above.

### Final review
One fresh reviewer on Opus over the whole range; fix Critical/Important in one pass with failing tests first.
