# Nephele Workers Management (Phase 2a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manage Cloudflare Workers from Nephele: list, settings, variables, secrets, routes, domains, cron triggers, versions, deploy and rollback, a native code editor, live logs, templates and delete.

**Architecture:** New `Workers*.swift` files in `CloudflareKit` (typed endpoints over `CFClient`, plus raw/multipart primitives that preserve binding JSON exactly). App side: one `WorkersStore` (list) and one `WorkerStore` per open Worker, a shared `ConfirmGate` for named confirmations, and a `WorkersView` with a per-Worker tabbed detail. Saving code uploads a **version**; deploying is a separate confirmed step.

**Tech Stack:** Swift 6 (language mode 6), SwiftUI macOS 26, URLSession (+ `URLSessionWebSocketTask`), Swift Testing, `StubServer`, XcodeGen. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-21-workers-management-design.md` (parent: `2026-11-21-cloudflare-mac-app-design.md`).

## Global Constraints
- macOS 26+, Swift 6 strict concurrency, pure Swift, no new dependencies.
- Reuse `CFClient`, `LoadState`, `Session` (`client`, `handle(_:)`, `selectedAccountID`), `LoadStateView`, `StubServer`, `TestAPI` (see `NepheleTests/Support.swift`). Do not refactor `DNSStore`.
- TDD for every Kit and store change; run Kit tests with `swift test --package-path Packages/CloudflareKit` and app tests with `xcodegen && xcodebuild test -scheme Nephele -destination 'platform=macOS'`.
- Secrets are write-only: never stored in state after send, never in errors or logs.
- Every removal, rollback, deploy and delete is confirmed through `ConfirmGate` naming the target; deleting a Worker requires typing its name.
- Saving code says "creates a new version"; deploy is separate; deployments are 100% to one version.
- Worker names: 1 to 63 chars, lowercase letters, digits, hyphens, not starting or ending with a hyphen. Cron: exactly 5 whitespace-separated fields. Version/deployment message: required for versions, at most 1000 bytes.
- Sentence case copy, no emoji, status as dots, one accent (existing theme tokens).
- No tokens, account ids or real names in fixtures, tests or docs. Public-repo hygiene as in phase 1.
- Fixtures are written from Cloudflare's OpenAPI response schemas (query them with the Cloudflare MCP `search` tool, product `workers`), not from a live account. Record in the ledger that live shapes are unconfirmed.

## Review Focus
- A Worker with many bindings and extra modules: saving code must not drop any binding or module (round-trip tests in Tasks 1 and 6).
- A token without write scope: the first 403 flips `canWrite` false and write controls disable with "needs Workers Scripts Edit" (Task 3). Ruling vs spec: the token's scopes cannot be read cheaply, so controls start enabled and disable after the first forbidden write rather than before.
- Invalid names, cron expressions and route patterns are rejected before any request (Tasks 3, 4, 8).
- Secret values never appear in state, errors or descriptions after sending (Task 3).
- Overview where some panels are forbidden and others load; rate limiting during the six parallel loads (Task 2).

---

### Task 1: Transport primitives (JSONValue, raw, download, multipart)

**Files:**
- Create: `Packages/CloudflareKit/Sources/CloudflareKit/JSONValue.swift`, `Multipart.swift`
- Modify: `Packages/CloudflareKit/Sources/CloudflareKit/CFClient.swift`
- Test: `Packages/CloudflareKit/Tests/CloudflareKitTests/TransportTests.swift`

**Interfaces:**
- Produces:
  - `public enum JSONValue: Codable, Sendable, Equatable, Hashable { case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue]) }` with subscript `[key] -> JSONValue?` on objects and `var stringValue: String?`.
  - `CFClient.raw(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, contentType: String = "application/json") async throws -> Data`: performs the request through the existing retry/status handling, validates the Cloudflare envelope exactly as `send` does, and returns the **whole response body bytes** so callers can decode with a plain `JSONDecoder` (no key conversion, so binding key names survive).
  - `CFClient.download(_ path: String) async throws -> (data: Data, headers: [String: String])`: GET without envelope decoding (script content is not an envelope); maps 401/403/other statuses to `CloudflareError` as `perform` does; header names lowercased.
  - `public struct MultipartForm: Sendable { init(boundary: String = UUID().uuidString); mutating func addJSON(name: String, _ value: Data); mutating func addFile(name: String, filename: String, contentType: String, data: Data); var body: Data; var contentType: String }` and `public struct MultipartPart: Sendable, Equatable { name: String?; filename: String?; contentType: String?; data: Data }` with `static func MultipartForm.parse(_ data: Data, contentType: String) -> [MultipartPart]`.

- [ ] **Step 1: Write failing tests** in `TransportTests.swift`: `jsonValueRoundTripsUnknownKeysExactly` (decode `{"my_var":{"nested_key":[1,"a",null,true]}}` and re-encode: equal bytes after canonical sort); `rawReturnsBodyBytesAndKeepsSnakeCaseKeys`; `rawThrowsPermissionDeniedOn403WithEnvelopeMessage`; `downloadReturnsBytesAndLowercasedHeaders` (stub sets `cf-entrypoint: index.js`); `multipartBuildsPartsWithBoundaryAndContentType`; `multipartParseRoundTripsTwoFilesIncludingBinaryBytes`.
- [ ] **Step 2: Run** `swift test --package-path Packages/CloudflareKit --filter TransportTests`. Expected: FAIL (types and methods undefined).
- [ ] **Step 3: Implement** the interfaces above. `raw` and `download` reuse `perform` (extend `perform` to take a `contentType` and return headers).
- [ ] **Step 4: Run the whole Kit suite.** Expected: PASS, previous 57 tests still green.
- [ ] **Step 5: Commit** `feat(kit): raw, download and multipart primitives`.

---

### Task 2: Workers list, overview, sidebar route

**Files:**
- Create: `Packages/CloudflareKit/Sources/CloudflareKit/Workers.swift`, `Packages/CloudflareKit/Tests/CloudflareKitTests/WorkersTests.swift`, fixtures `workers-list.json`, `workers-deployments.json`
- Create: `Nephele/Shared/ConfirmGate.swift`, `Nephele/Workers/WorkersStore.swift`, `Nephele/Workers/WorkerStore.swift`, `Nephele/Views/WorkersView.swift`, `Nephele/Views/WorkerDetailView.swift`
- Modify: `Nephele/Settings/AppSettings.swift` (add `.workers` to `Route`), `Nephele/Shell/Route+UI.swift` (title "Workers", symbol `curlybraces`), `Nephele/Shell/AppShell.swift`, `Nephele/NepheleApp.swift` (create/reset `WorkersStore`), `Packages/CloudflareKit/Sources/CloudflareKit/Account.swift` (probe row), tests `AccountTests`, `NepheleTests/WorkersStoreTests.swift`, `NepheleTests/ConfirmGateTests.swift`, `NepheleTests/NavigatorTests.swift`

**Interfaces:**
- Produces (Kit): `WorkerScript: Codable, Sendable, Identifiable, Hashable { id: String (the name); createdOn: Date?; modifiedOn: Date?; compatibilityDate: String?; handlers: [String]? }`; `WorkerDeployment: Codable, Sendable, Identifiable, Equatable { id; createdOn: Date; message: String?; versions: [DeploymentVersion] }`, `DeploymentVersion { versionId: String; percentage: Double }`; `CFClient.workers(accountID: String) async throws -> [WorkerScript]`; `CFClient.deployments(accountID: String, script: String) async throws -> [WorkerDeployment]` (newest first).
- Produces (App): `@MainActor @Observable final class ConfirmGate<Item: Equatable & Sendable>` with `private(set) var pending: Item?`, `request(_:)`, `cancel()`, `dialogDismissed()`, `func take(_ item: Item) -> Bool` (true only if `item` is the armed request; clears armed, exactly once). Same armed/pending separation as `DNSStore`. `WorkersStore(session:)`: `workers: LoadState<[WorkerScript]>`, `load(force:)`, `reset()`. `WorkerStore(script: WorkerScript, session: Session)`: `latestDeployment: LoadState<WorkerDeployment?>`, `canWrite: Bool = true`, `func noteWriteDenied()` (sets `canWrite = false`), `load()`.
- Probe: `probePermissions` gains a "Workers" row hitting `GET /accounts/{id}/workers/scripts`; the test counts become 10 (with zone) and 9 (without).

- [ ] **Step 1: Write failing tests.** Kit: `workersDecodesFixture` (two scripts, names `hello-api` and `cron-job`, `modifiedOn` parsed), `deploymentsDecodeNewestFirst`, `workersRequestPathIsAccountScripts`. App: `ConfirmGateTests` (`takeSucceedsOnlyForArmedItemAndOnlyOnce`, `dialogDismissedKeepsArmed`, `cancelClearsArmed`); `WorkersStoreTests` (`loadsIntoLoadedState`, `permissionDeniedBecomesFailedAndNotifiesSession`, `resetClearsData`, `forbiddenDeploymentsDoNotBlockScriptList`); `NavigatorTests` (workers route exists and is visible in default nav, nav repair adds it to a saved settings blob that lacks it).
- [ ] **Step 2: Run both suites filtered to the new tests.** Expected: FAIL (types undefined).
- [ ] **Step 3: Implement** Kit models and the two calls (`getAll`-free: scripts list is a single call; decode with `get`). Implement `ConfirmGate`, stores, `.workers` route, sidebar wiring, `WorkersView` (searchable list, `LoadStateView` with permission "Workers Scripts Read", row shows name, "Updated <relative>", handlers as small labels) and `WorkerDetailView` (header with name, tab picker: Overview, Settings, Triggers, Versions, Code, Logs; only Overview built here, other tabs show a "Coming next" `ContentUnavailableView` that later tasks replace). Overview shows latest deployment (version id prefix, message, date) and a triggers summary placeholder filled in Task 4.
- [ ] **Step 4: Run Kit and app suites.** Expected: PASS. `ViewSmokeTests`: add a render of `WorkersView` with two fake scripts.
- [ ] **Step 5: Commit** `feat: workers list and overview`.

---

### Task 3: Settings, variables, secrets

**Files:**
- Create: `Packages/CloudflareKit/Sources/CloudflareKit/WorkerSettings.swift`, fixtures `worker-settings.json`, `worker-secrets.json`, `Nephele/Views/WorkerSettingsView.swift`
- Modify: `Nephele/Workers/WorkerStore.swift`, `WorkerDetailView.swift`
- Test: `Packages/CloudflareKit/Tests/CloudflareKitTests/WorkerSettingsTests.swift`, `NepheleTests/WorkerSettingsStoreTests.swift`

**Interfaces:**
- Consumes: `CFClient.raw` (Task 1), `ConfirmGate` and `WorkerStore.canWrite`/`noteWriteDenied` (Task 2).
- Produces (Kit):
  - `WorkerBinding: Sendable, Equatable, Identifiable { name: String; type: String; fields: [String: JSONValue] }` (full raw object kept so nothing is lost).
  - `WorkerSettings: Sendable, Equatable { compatibilityDate: String?; compatibilityFlags: [String]; observabilityEnabled: Bool; bindings: [WorkerBinding]; var plainVars: [WorkerBinding] (type == "plain_text") }`.
  - `CFClient.workerSettings(accountID:script:) async throws -> WorkerSettings`.
  - `CFClient.updateWorkerSettings(accountID:script:_ change: WorkerSettingsChange) async throws -> WorkerSettings` where `WorkerSettingsChange { compatibilityDate: String?; compatibilityFlags: [String]?; observabilityEnabled: Bool?; bindings: [WorkerBinding]? }` encodes only non-nil fields. Verify the PATCH body content type first (`search` spec for `PATCH .../settings` requestBody; expected multipart with a `settings` JSON part) and ledger the result.
  - `CFClient.workerSecretNames(accountID:script:) async throws -> [String]`, `setWorkerSecret(accountID:script:name:value:) async throws`, `deleteWorkerSecret(accountID:script:name:) async throws`.
  - `CFClient.workersDevSubdomain(accountID:script:) async throws -> Bool` and `setWorkersDevSubdomain(accountID:script:enabled:) async throws` (POST enable, DELETE disable).
  - `WorkerNameValidation` free function `validWorkerName(_:) -> Bool` (also used in Task 8) and `validBindingName(_:) -> Bool` (JS identifier: letters, digits, `_`, `$`, not starting with a digit).
- Produces (App): `WorkerStore` gains `settings: LoadState<WorkerSettings>`, `secretNames: LoadState<[String]>`, `formError: String?`, `confirm: ConfirmGate<WorkerChange>` with `enum WorkerChange: Equatable, Sendable { case removeVar(String), deleteSecret(String), toggleWorkersDev(Bool), removeBinding(String) }` (each with a `title`/`message` naming the Worker and target), and methods `saveSettings(_:)`, `setVar(name:value:)`, `setSecret(name:value:)`, `confirmChange(_:)`.

- [ ] **Step 1: Write failing tests.** Kit: `settingsDecodePreservesBindingFieldsExactly` (a KV binding with `namespace_id` round-trips byte-equal), `updateOmitsNilFields`, `secretNamesNeverContainValues`, `setSecretSendsValueOnlyInBody`, `validBindingNames`, `validWorkerNameRules` (accepts `hello-api`, rejects `-a`, `A`, 64 chars, empty). App: `setVarWithInvalidNameShowsErrorWithoutRequest`, `forbiddenWriteDisablesControlsAndShowsEditHint`, `removeVarRequiresConfirmationNamingWorkerAndVar`, `secretValueIsNotInStateErrorsOrDescriptionAfterSend` (store a sentinel string, assert absent from `String(describing:)` of the store state, `formError`, and the thrown error), `settingsPatchKeepsOtherBindingsUnchanged`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** Kit calls and store methods; `WorkerSettingsView` with compatibility date field, `nodejs_compat` toggle, observability toggle, workers.dev toggle (confirmed), a variables table (add/edit/remove), a secrets list (names only, "Set value" sheet with `SecureField`, value cleared on send), and bindings list read-only except remove (confirmed). Write controls use `.disabled(!store.canWrite)` with a help hint "Needs a token with Workers Scripts Edit".
- [ ] **Step 4: Run both suites. Expected: PASS.**
- [ ] **Step 5: Commit** `feat: worker settings, variables and secrets`.

---

### Task 4: Routes, custom domains, cron triggers

**Files:**
- Create: `Packages/CloudflareKit/Sources/CloudflareKit/WorkerTriggers.swift`, fixtures `worker-routes.json`, `worker-domains.json`, `worker-schedules.json`, `Nephele/Views/WorkerTriggersView.swift`
- Modify: `WorkerStore.swift`, `WorkerDetailView.swift`
- Test: `WorkerTriggersTests.swift` (Kit), `WorkerTriggersStoreTests.swift` (app)

**Interfaces:**
- Consumes: `ConfirmGate`, `WorkerChange` (extend with `removeRoute(id)`, `detachDomain(id)`, `replaceSchedules`), `Zone` list from `DomainsStore`.
- Produces (Kit): `WorkerRoute { id, pattern: String, script: String? }`; `WorkerDomain { id, hostname: String, zoneName: String?, service: String }`; `CFClient.workerRoutes(zoneID:) -> [WorkerRoute]`, `createWorkerRoute(zoneID:pattern:script:)`, `deleteWorkerRoute(zoneID:id:)`; `workerDomains(accountID:)`, `attachWorkerDomain(accountID:hostname:script:zoneID:)`, `detachWorkerDomain(accountID:id:)`; `workerSchedules(accountID:script:) -> [String]`, `setWorkerSchedules(accountID:script:_ crons:[String])`; validators `validRoutePattern(_ pattern: String, zone: String) -> Bool` (host part equals or is a subdomain of the zone, optional leading `*.` or trailing `/*`) and `validCron(_:) -> Bool` (exactly 5 whitespace-separated fields of `[0-9*/,-]` plus names).
- Produces (App): `WorkerStore.triggers: LoadState<WorkerTriggers>` (routes for this Worker across zones, domains, crons). Routes load per zone with at most 4 concurrent requests; a forbidden zone is skipped and listed as "Couldn't read routes for example.dev".

- [ ] **Step 1: Write failing tests.** Kit: `routesCreateBodyHasPatternAndScript`, `schedulesPutBodyShape`, `validRoutePatternAcceptsSubdomainAndWildcardRejectsOtherZone`, `validCronRejectsFourFieldsAndLetters`, `domainsFilterToThisWorker`. App: `invalidCronShowsErrorAndSendsNothing`, `invalidRoutePatternSendsNothing`, `removingCronOrRouteNeedsConfirmation`, `oneForbiddenZoneDoesNotHideOtherRoutes`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** Kit calls and validators, store methods, `WorkerTriggersView` (three sections with add forms and per-row remove). Fill the Overview triggers summary from this store.
- [ ] **Step 4: Run both suites. Expected: PASS.**
- [ ] **Step 5: Commit** `feat: worker routes, domains and cron triggers`.

---

### Task 5: Versions, deployments, rollback

**Files:**
- Create: `Packages/CloudflareKit/Sources/CloudflareKit/WorkerVersions.swift`, fixtures `worker-versions.json`, `worker-deployment-created.json`, `Nephele/Views/WorkerVersionsView.swift`
- Modify: `WorkerStore.swift`, `WorkerDetailView.swift`
- Test: `WorkerVersionsTests.swift` (Kit), `WorkerVersionsStoreTests.swift` (app)

**Interfaces:**
- Consumes: `CFClient.deployments` and `WorkerDeployment` (Task 2), `ConfirmGate`/`WorkerChange` (extend with `deploy(versionID: String, label: String)`).
- Produces (Kit): `WorkerVersion: Codable, Sendable, Identifiable, Equatable { id: String; number: Int?; createdOn: Date?; message: String?; authorEmail: String? }`; `CFClient.workerVersions(accountID:script:) -> [WorkerVersion]` (newest first); `CFClient.deployVersion(accountID:script:versionID:message:) async throws -> WorkerDeployment` posting `{"strategy":"percentage","versions":[{"percentage":100,"version_id":<id>}],"annotations":{"workers/message":<message>}}`.
- Produces (App): `WorkerStore.versions: LoadState<[WorkerVersion]>`, `deployments: LoadState<[WorkerDeployment]>`; `requestDeploy(version:)` arms a `.deploy` change whose message reads "Deploy version <short id> of <worker> to 100% of traffic?" and, when the version is older than the current one, "Roll back to version …"; `confirmChange` sends it exactly once and refreshes deployments. A `currentVersionID` derived from the newest deployment marks the live row.

- [ ] **Step 1: Write failing tests.** Kit: `deployBodyIsHundredPercentSingleVersion`, `versionsDecodeNewestFirst`, `messageLongerThan1000BytesIsRejectedBeforeSending`. App: `deployNeedsConfirmationAndSendsOnce`, `rollbackWordingUsedForOlderVersion`, `deployingTheLiveVersionIsDisabled`, `forbiddenDeployDisablesWritesAndKeepsList`, `refreshAfterDeployUpdatesLiveMarker`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** `WorkerVersionsView` lists versions with a live dot on the current one, message, relative date, and a "Deploy" or "Roll back" button.
- [ ] **Step 4: Run both suites. Expected: PASS.**
- [ ] **Step 5: Commit** `feat: worker versions, deploy and rollback`.

---

### Task 6: Code editor (save as new version)

**Files:**
- Create: `Packages/CloudflareKit/Sources/CloudflareKit/WorkerCode.swift`, fixtures `worker-content-multipart.txt` (multipart body, `cf-entrypoint: index.js`), `Nephele/Views/WorkerCodeView.swift`
- Modify: `WorkerStore.swift`, `WorkerDetailView.swift`
- Test: `WorkerCodeTests.swift` (Kit), `WorkerCodeStoreTests.swift` (app)

**Interfaces:**
- Consumes: `MultipartForm`/`parse` and `download` (Task 1), `WorkerSettings`/`WorkerBinding` (Task 3), `WorkerVersion` (Task 5).
- Produces (Kit): `WorkerModule: Sendable, Equatable { name: String; contentType: String; data: Data; var text: String? }`; `WorkerCode: Sendable, Equatable { mainModule: String; modules: [WorkerModule] }`; `CFClient.workerCode(accountID:script:) async throws -> WorkerCode` (GET `.../content/v2`, main module from `cf-entrypoint`, parts parsed with `MultipartForm.parse`); `CFClient.uploadVersion(accountID:script:code: WorkerCode, settings: WorkerSettings, message: String) async throws -> WorkerVersion` (POST `.../versions`, multipart: a `metadata` JSON part with `main_module`, `compatibility_date`, `compatibility_flags`, `keep_bindings` set to the distinct binding types of `settings.bindings`, and `annotations["workers/message"]`; one file part per module with its original name and content type).
- Produces (App): `WorkerStore.code: LoadState<WorkerCode>`, `draft: String` (main module text), `var hasUnsavedChanges: Bool`, `saveVersion(message:) async` (requires non-empty message, sends all modules with only the main module's text replaced), `message` validation error in `formError`.

- [ ] **Step 1: Write failing tests.** Kit: `workerCodeParsesEntrypointAndExtraModules`, `uploadVersionResendsUntouchedModulesByteForByte`, `uploadVersionSetsKeepBindingsForEveryExistingBindingType`, `uploadVersionPutsMessageInAnnotations`, `binaryModuleSurvivesRoundTrip`. App: `saveWithEmptyMessageShowsErrorAndSendsNothing`, `saveReplacesOnlyMainModuleText`, `unsavedGuardTracksDraftVersusLoaded`, `saveDoesNotDeploy` (stub records no `/deployments` POST), `nonUTF8MainModuleIsReadOnlyWithExplanation`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** `WorkerCodeView`: monospaced `TextEditor` (font from existing Appearance tokens), line/char count, "Save as new version" opens a message sheet noting "This creates a new version. It isn't live until you deploy it." After success, switch to the Versions tab with the new version highlighted. Extra modules listed read-only above the editor. Leaving the tab or Worker with unsaved changes shows a confirmation.
- [ ] **Step 4: Run both suites. Expected: PASS.**
- [ ] **Step 5: Commit** `feat: worker code editor with version save`.

---

### Task 7: Live log tail

**Files:**
- Create: `Packages/CloudflareKit/Sources/CloudflareKit/WorkerTail.swift`, `Nephele/Workers/TailStore.swift`, `Nephele/Views/WorkerLogsView.swift`, fixture `tail-events.json`
- Test: `WorkerTailTests.swift` (Kit), `TailStoreTests.swift` (app)

**Interfaces:**
- Produces (Kit): `TailSession: Sendable { id: String; url: URL; expiresAt: Date? }`; `CFClient.startTail(accountID:script:) async throws -> TailSession` (POST `.../tails`; the response carries `id`, `url`, `expires_at`); `CFClient.stopTail(accountID:script:id:)`; `TailEvent: Sendable, Identifiable, Equatable { id: UUID; time: Date; outcome: String; method: String?; url: String?; logs: [TailLogLine]; exceptions: [String] }` and `TailEvent.parse(_ data: Data) -> TailEvent?` (message JSON from the socket: `outcome`, `eventTimestamp` in ms, `event.request.url/method`, `logs[].level/message`, `exceptions[].name/message`); `var isError: Bool` (outcome != "ok" or any exception or an `error`-level log).
- Produces (App): `TailStore(session:, script:, openSocket: @escaping (URL) -> AsyncStream<Data>)` (default uses `URLSessionWebSocketTask`): `events: [TailEvent]` capped at 500 (oldest dropped), `state` (idle, connecting, live, stopped(reason)), `errorsOnly: Bool` with `visibleEvents`, `start()`, `stop()` (also calls `stopTail`). A sampling-warning message in the socket (a JSON object with `message` containing "sampl") sets `samplingNotice`. A start failure with the 10-viewer limit shows "Too many people are watching this Worker's logs. Try again shortly."

- [ ] **Step 1: Write failing tests** (socket injected as an `AsyncStream`): Kit `tailEventParsesRequestLogsAndExceptions`, `isErrorTrueForExceptionAndErrorLevelLog`, `startTailDecodesUrlAndId`, `parseIgnoresMalformedMessage`. App `startConnectsAndAppendsEvents`, `errorsOnlyFiltersVisibleEvents`, `buffer capped at 500 dropping oldest`, `stopCallsStopTailOnce`, `samplingMessageSetsNotice`, `startFailureShowsFriendlyMessage`, `leavingTheViewStopsTheTail` (store `stop()` is idempotent).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** `WorkerLogsView`: Start/Stop button, "Errors only" toggle, monospaced list newest at bottom with auto-scroll, status dot, clear button. Stop on `onDisappear`. Cookies/tokens are never sent over the socket (the URL itself carries access).
- [ ] **Step 4: Run both suites. Expected: PASS.**
- [ ] **Step 5: Commit** `feat: worker live log tail`.

---

### Task 8: Templates, delete, permissions copy, docs

**Files:**
- Create: `Packages/CloudflareKit/Sources/CloudflareKit/WorkerTemplates.swift`, `Nephele/Views/NewWorkerSheet.swift`
- Modify: `WorkerStore.swift`/`WorkersStore.swift`, `WorkersView.swift`, `Nephele/Views/SettingsView.swift` (permission checklist rows for Workers), `README.md`, `docs/superpowers/specs/2026-11-21-workers-management-design.md` (note: tail start response confirmed as id/url/expires_at; `keep_bindings` used)
- Test: `WorkerTemplatesTests.swift`, `NepheleTests/WorkersCreateDeleteTests.swift`

**Interfaces:**
- Consumes: `validWorkerName` (Task 3), `uploadVersion`/`deployVersion` (Tasks 5, 6), `ConfirmGate` (Task 2).
- Produces: `WorkerTemplate: CaseIterable { hello, httpAPI, scheduledJob }` with `var source: String`, `var title: String`, `var cron: String?`; `CFClient.createWorker(accountID:name:template:) async throws -> WorkerVersion` (uploads template as first version through `/versions` with `compatibility_date` = today and message "Created from template: <title>"; the user then deploys it from the Versions tab, the sheet says so); `CFClient.deleteWorker(accountID:script:force:)` (DELETE `.../{name}`); `WorkersStore.create(name:template:)`, `requestDelete(_ script:)`; delete requires `typedName == script.id`.

- [ ] **Step 1: Write failing tests.** `everyTemplateHasAnExportDefaultFetchOrScheduledHandler`, `scheduledTemplateCarriesFiveFieldCron`, `createRejectsInvalidAndDuplicateNamesBeforeRequest`, `createUploadsVersionNotDeployment`, `deleteRequiresTypingExactName`, `deleteRemovesFromListAfterSuccess`, `deleteForbiddenKeepsWorkerAndShowsHint`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** New Worker sheet: name field with live validation, template picker, "Create version" button. Delete: toolbar item on detail view opens a sheet with a name field, button disabled until it matches. Update Settings permission checklist and README feature list and the permissions table (Workers Scripts Read/Write, Workers Tail Read, Workers Routes Read/Write).
- [ ] **Step 4: Run both suites in full; render `ViewSmokeTests` for each Workers tab.** Expected: all PASS (Kit and app, counts higher than 57 and 90).
- [ ] **Step 5: Commit** `feat: worker templates, delete and docs`.

---

## Self-review notes
- **Coverage:** spec items map to Tasks: list/overview (2), settings/vars/secrets/bindings/workers.dev (3), routes/domains/cron (4), versions/rollback (5), editor (6), tail (7), templates/delete (8).
- **Known unconfirmed shapes** (ledger at execution): `PATCH .../settings` body type; `content/v2` multipart details; `keep_bindings` semantics for non-secret bindings. The round-trip tests in Tasks 3 and 6 are the guard; the owner must try a save on a throwaway Worker before relying on it.
- **Owner verification needed before beta use:** live deploy and rollback on a throwaway Worker; live log tail; secret set/delete on a throwaway Worker. None can be done without the owner's token.
