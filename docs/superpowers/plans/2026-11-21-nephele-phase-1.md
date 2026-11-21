# Nephele Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A runnable macOS 26 app, Nephele, that signs in with a Cloudflare API token and shows an account overview, domains with full DNS management, alerts (with notifications and a menu bar item), usage, an app Settings screen and a full Appearance screen.

**Architecture:** Pure Swift. `CloudflareKit` (local Swift package, no UI) owns the typed API client, models, validation and alert de-duplication. The app target owns SwiftUI views, `@Observable` stores (one per area), Keychain and settings persistence. A second package library, `CloudflareKitTesting`, holds the URLProtocol stub both test targets use.

**Tech Stack:** Swift 6 (language mode 6), SwiftUI, Swift Charts, Swift Testing (`import Testing`), URLSession async/await, Security (Keychain), UserNotifications, ServiceManagement, XcodeGen for the `.xcodeproj`.

**Spec:** `docs/superpowers/specs/2026-11-21-cloudflare-mac-app-design.md`. Reference mockup: https://claude.ai/artifact/4Fi4dSeLGz83aoR1eac9aq (visual and behaviour reference; plan wins where they differ).

**Scope:** This plan is phase 1 only (spec "Phasing" item 1). Workers, Pages, R2/D1/KV management (phase 2), Zero Trust (phase 3) and the rest get their own plans after phase 1 ships. Sidebar entries for them are not shown until those plans land.

**Deliberate deviations from the spec**
- "Sidebar side: right" from the mockup is dropped for v1. `NavigationSplitView` keeps the Liquid Glass sidebar native and only supports the leading edge. Amend the spec if the owner wants it back.
- XcodeGen is a dev-time dependency (not shipped) so the project file is reproducible and reviewable.

## Global Constraints

- macOS 26+ deployment target (`26.0`), Swift 6, SwiftUI, Swift Package Manager for packages.
- No Rust, no FFI, no helper process, no server component. The app talks only to the Cloudflare API (REST v4 and GraphQL Analytics).
- API token lives in the Keychain only. Never in UserDefaults, logs, error text, fixtures or the repo.
- Cloudflare rate limit is about 1200 requests per 5 minutes per token: client backs off on 429 and screens cache results.
- Token scopes decide what each area shows: a missing permission shows a clear "token lacks permission X" state, never an error wall.
- Any destructive or hard-to-reverse change (delete record, delete Worker, purge) needs an explicit confirmation naming the target.
- Read-first: every area is browsable before it is editable.
- No analytics or telemetry of any kind.
- Public-repo ready from the first commit: GitHub handle `Ol775` only (commit identity `Ol775 <Ol775@users.noreply.github.com>`), MIT licence, no real name, personal email, real account IDs or real domains in code, history, fixtures or screenshots (use `example.*` domains and fake IDs).
- Sentence case for all UI copy; British English.
- Bundle ID `io.github.ol775.nephele`; app name "Nephele".

## Review Focus

1. Token has only some permissions: affected screens show a "token lacks permission" state and the rest still work. (Tasks 3, 11)
2. Account with zero zones, zone with zero DNS records, no alerts: each shows a designed empty state, not a blank view. (Tasks 4, 5, 11, 12)
3. More than one page of results (over 50 zones, over 100 DNS records, many alert events): everything is fetched, nothing silently truncated. (Task 2, 4)
4. DNS drafts: apex "@", relative and uppercase names, proxied set on a type that cannot be proxied, MX without priority. (Task 5)
5. Network drop, 429 or revoked token mid-polling: last good data stays on screen, no duplicate or lost notifications, and a revoked token returns to sign-in. (Tasks 2, 6, 10, 12)

---

### Task 1: Scaffold, licence and repo

**Files:**
- Create: `.gitignore`, `LICENSE` (MIT, "Copyright (c) 2026 Ol775"), `README.md` (name, one-line purpose, build steps from this task), `project.yml`
- Create: `Packages/CloudflareKit/Package.swift`, `Packages/CloudflareKit/Sources/CloudflareKit/CloudflareKit.swift`, `Packages/CloudflareKit/Sources/CloudflareKitTesting/StubURLProtocol.swift`, `Packages/CloudflareKit/Tests/CloudflareKitTests/SmokeTests.swift`
- Create: `Nephele/NepheleApp.swift`, `NepheleTests/SmokeTests.swift`

**Interfaces:**
- Produces: package products `CloudflareKit` and `CloudflareKitTesting` (swift-tools-version 6.0, `platforms: [.macOS(.v26)]`); app scheme `Nephele` and test scheme target `NepheleTests`, both depending on the local package; `StubURLProtocol` with `static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?` and `static func session() -> URLSession` (ephemeral configuration with this protocol registered).

- [ ] **Step 1: Write failing smoke tests.** Kit: `@Test func versionIsSet() { #expect(CloudflareKit.version == "0.1.0") }`. App: `@Test func appBundleIdentifier() { #expect(Bundle.main.bundleIdentifier == "io.github.ol775.nephele") }`.
- [ ] **Step 2: Run to confirm failure.** `swift test --package-path Packages/CloudflareKit` fails (no target yet).
- [ ] **Step 3: Create the package and app.** `project.yml` (XcodeGen): app target `Nephele` (macOS 26.0, Swift 6, bundle ID above, App Sandbox + outgoing network entitlement, `LSUIElement` false), unit test target `NepheleTests` hosted by the app, package dependency on the local path with both products. `NepheleApp` is a `@main App` with a `WindowGroup { Text("Nephele") }`. Run `brew install xcodegen` if missing, then `xcodegen generate`.
- [ ] **Step 4: Verify.** `swift test --package-path Packages/CloudflareKit` passes; `xcodebuild test -scheme Nephele -destination 'platform=macOS'` passes.
- [ ] **Step 5: Commit.** `git init -b main`, `git config user.name Ol775`, `git config user.email Ol775@users.noreply.github.com`, add everything except generated `Nephele.xcodeproj` (ignored), commit `chore: scaffold Nephele app and CloudflareKit`.

### Task 2: API client core

**Files:**
- Create: `Packages/CloudflareKit/Sources/CloudflareKit/CFClient.swift`, `CFEnvelope.swift`, `CFError.swift`
- Test: `Packages/CloudflareKit/Tests/CloudflareKitTests/CFClientTests.swift`

**Interfaces:**
- Produces:
  - `public struct CFEnvelope<T: Decodable & Sendable>: Decodable, Sendable { success: Bool; errors: [CFAPIMessage]; result: T?; resultInfo: CFResultInfo? }`, `CFAPIMessage { code: Int; message: String }`, `CFResultInfo { page: Int; perPage: Int; totalPages: Int; totalCount: Int }` (snake_case keys decoded with `.convertFromSnakeCase`).
  - `public enum CFError: Error, Sendable, Equatable { case unauthorized; case permissionDenied(String?); case rateLimited(retryAfter: TimeInterval?); case api(code: Int, message: String); case transport(String); case decoding(String) }`
  - `public actor CFClient { public init(token: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://api.cloudflare.com/client/v4")!); public func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> CFEnvelope<T>; public func getAll<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [], perPage: Int) async throws -> [T]; public func send<T: Decodable & Sendable>(_ method: String, _ path: String, body: (any Encodable & Sendable)? = nil) async throws -> T; public func graphQL<T: Decodable & Sendable>(_ query: String, variables: (any Encodable & Sendable)? = nil) async throws -> T }`
- Consumes: `StubURLProtocol` from Task 1.

- [ ] **Step 1: Write failing tests** (all use `StubURLProtocol.session()` and inline JSON with fake data): `decodesEnvelopeAndSendsBearerHeader` (asserts `Authorization: Bearer <token>`); `maps401ToUnauthorized`; `maps403ToPermissionDenied`; `retriesOn429HonouringRetryAfter` (first reply 429 with `Retry-After: 0`, second 200; expect result and exactly 2 requests); `givesUpAfterThreeRateLimitRetries` (throws `.rateLimited`); `getAllFollowsPagination` (3 pages of 2 items: expect 6 items and `page=1,2,3` seen); `getAllWithOnePageReturnsThatPage`; `surfacesApiErrorsFromEnvelope` (`success:false`, code 1004 maps to `.api(code:1004, message:)`); `neverLeaksTokenInErrors` (token `tok_SECRET123`: `String(describing: error)` and `error.localizedDescription` for every error case produced above do not contain it).
- [ ] **Step 2: Run to confirm they fail.** `swift test --package-path Packages/CloudflareKit --filter CFClientTests`.
- [ ] **Step 3: Implement the types above.** Retry only on 429 and transient `URLError` (`.timedOut`, `.networkConnectionLost`), at most 3 attempts, sleeping `Retry-After` seconds (default 1, doubling). `getAll` loops until `resultInfo.totalPages`. `CFError` conforms to `LocalizedError` with user-facing copy that never interpolates request headers.
- [ ] **Step 4: Run to confirm they pass.**
- [ ] **Step 5: Commit.** `feat(kit): API client with pagination, backoff and typed errors`

### Task 3: Token verification and permission probe

**Files:**
- Create: `Sources/CloudflareKit/Account.swift`
- Test: `Tests/CloudflareKitTests/AccountTests.swift`

**Interfaces:**
- Consumes: `CFClient.get`.
- Produces: `public struct TokenStatus: Sendable, Equatable { id: String; status: String }`; `public struct CFAccount: Decodable, Sendable, Identifiable, Equatable { id: String; name: String }`; `public struct PermissionStatus: Sendable, Equatable, Identifiable { name: String; level: String; granted: Bool }`; `extension CFClient { public func verifyToken() async throws -> TokenStatus; public func accounts() async throws -> [CFAccount]; public func probePermissions(accountID: String, zoneID: String?) async -> [PermissionStatus] }`.

- [ ] **Step 1: Write failing tests:** `verifyTokenDecodesActiveStatus` (`GET /user/tokens/verify`); `verifyTokenThrowsUnauthorizedOnInvalid`; `probeMarksForbiddenEndpointsAsMissing` (stub: zones 200, `/accounts/x/tunnels` 403, `/accounts/x/r2/buckets` 403 -> exactly those two `granted == false`) (Review Focus 1); `probeNeverThrows` (all endpoints fail with transport errors -> still returns the full list, all `granted == false`).
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement.** The probe issues one cheap `per_page=1` GET per permission and treats only 403 as "missing" (network errors also report not granted but do not throw). Checklist rows and what is probed: Zone (zones), DNS (dns_records of `zoneID`, skipped when nil), Workers Scripts (account workers scripts), Workers KV (kv namespaces), D1 (d1 database), Workers R2 Storage (r2 buckets), Access apps (access apps), Cloudflare Tunnel (cfd_tunnel), Account Analytics (alerting policies). Level text is "Read (edit not checked)" because edit cannot be probed without writing.
- [ ] **Step 4: Run to confirm pass.**
- [ ] **Step 5: Commit.** `feat(kit): token verification and permission probe`

### Task 4: Zones

**Files:**
- Create: `Sources/CloudflareKit/Zones.swift`; `Tests/CloudflareKitTests/Fixtures/zones-page1.json`, `zones-page2.json` (fake data, `example.*` names); `ZonesTests.swift`

**Interfaces:**
- Produces: `public struct Zone: Decodable, Sendable, Identifiable, Equatable { id: String; name: String; status: String; paused: Bool; planName: String; nameServers: [String]; accountID: String }` (decode `plan.name`, `account.id` via a custom `init(from:)`); `extension CFClient { public func zones() async throws -> [Zone] }` (`getAll`, `perPage: 50`).

- [ ] **Step 1: Write failing tests:** `zonesMergesAllPages` (fixture 50 + 3 zones -> 53, requests `page=1,2`) (Review Focus 3); `zonesEmptyAccountReturnsEmptyArray` (Review Focus 2); `zoneDecodesPlanAndAccount`.
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement `Zone` and `zones()`.**
- [ ] **Step 4: Run to confirm pass.**
- [ ] **Step 5: Commit.** `feat(kit): zones`

### Task 5: DNS records and draft validation

**Files:**
- Create: `Sources/CloudflareKit/DNS.swift`; `Tests/CloudflareKitTests/DNSTests.swift`

**Interfaces:**
- Produces: `public struct DNSRecord: Codable, Sendable, Identifiable, Equatable { id: String; type: String; name: String; content: String; proxied: Bool?; ttl: Int; priority: Int? }`; `public struct DNSRecordDraft: Sendable, Equatable { var type: String; var name: String; var content: String; var proxied: Bool; var ttl: Int = 1; var priority: Int? }`; `public enum DNSValidationError: Error, Equatable, LocalizedError { case emptyName, emptyContent, notIPv4, notIPv6, notHostname, missingPriority }`; `extension DNSRecordDraft { public func validated(zone: String) throws -> DNSRecordDraft }`; `extension CFClient { public func dnsRecords(zoneID: String) async throws -> [DNSRecord]; public func createDNSRecord(zoneID: String, _ draft: DNSRecordDraft) async throws -> DNSRecord; public func updateDNSRecord(zoneID: String, id: String, _ draft: DNSRecordDraft) async throws -> DNSRecord; public func deleteDNSRecord(zoneID: String, id: String) async throws }`.

- [ ] **Step 1: Write failing tests** (Review Focus 4): `apexAtBecomesZoneName` (`@` on `example.dev` -> `example.dev`); `relativeNameGetsZoneSuffixAndLowercase` (`API` -> `api.example.dev`); `alreadyQualifiedNameIsKept`; `aRecordRequiresIPv4` (`192.0.2.10` ok, `999.1.1.1` and `abc` throw `.notIPv4`); `aaaaRequiresIPv6`; `cnameRequiresHostname`; `mxRequiresPriority`; `proxiedIsForcedFalseForMXAndTXT` (draft with `proxied: true` for TXT -> validated `false`); `emptyNameAndContentThrow`; `dnsRecordsMergesPagesOf100` (Review Focus 3, `perPage` 100); `emptyZoneReturnsNoRecords` (Review Focus 2); `createSendsValidatedBody` (asserts JSON body fields and method `POST`); `updateUsesPatch`; `deleteUsesDelete` (path `/zones/z1/dns_records/r1`). Error `errorDescription` strings: "A record needs an IPv4 address, such as 192.0.2.10." and "Enter a name and content for the record." (copy from mockup).
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement.** Validation is pure (no network). TTL `1` means automatic. IPv4/IPv6 checks use `IPv4Address`/`IPv6Address` from Network.framework (add `import Network`).
- [ ] **Step 4: Run to confirm pass.**
- [ ] **Step 5: Commit.** `feat(kit): DNS records and draft validation`

### Task 6: Alerting and de-duplication

**Files:**
- Create: `Sources/CloudflareKit/Alerts.swift`; `Tests/CloudflareKitTests/AlertsTests.swift`; fixtures `alert-policies.json`, `alert-history.json`

**Interfaces:**
- Produces: `public struct AlertPolicy: Decodable, Sendable, Identifiable, Equatable { id: String; name: String; alertType: String; enabled: Bool }`; `public struct AlertEvent: Decodable, Sendable, Identifiable, Equatable { id: String; name: String; alertType: String; sent: Date; severity: AlertSeverity }`; `public enum AlertSeverity: String, Codable, Sendable { case info, warning, critical }`; `extension CFClient { public func alertPolicies(accountID: String) async throws -> [AlertPolicy]; public func alertHistory(accountID: String) async throws -> [AlertEvent] }` (`/accounts/{id}/alerting/v3/policies` and `/history`); `public struct AlertDeduper: Codable, Sendable { public init(maxRemembered: Int = 500); public mutating func newEvents(_ events: [AlertEvent]) -> [AlertEvent] }`.

- [ ] **Step 1: Write failing tests:** `historyMapsKnownAlertTypesToSeverity` (map by `alert_type`: certificate/expiry -> warning, origin/5xx -> critical, otherwise info; asserted for three fixture rows); `emptyHistoryIsEmpty` (Review Focus 2); `dedupeReturnsEachEventOnce` (same batch twice -> second returns `[]`) (Review Focus 5); `dedupeKeepsOnlyMaxRemembered` (501 events with max 500: the oldest is forgotten); `dedupeStateRoundTripsThroughJSON`.
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement.** The first `newEvents` call after a fresh install must treat existing history as seen (no notification flood): `AlertDeduper` exposes `isPrimed`; the poller (Task 12) primes it silently.
- [ ] **Step 4: Run to confirm pass.**
- [ ] **Step 5: Commit.** `feat(kit): alerting API and de-duplication`

### Task 7: Analytics and usage

**Files:**
- Create: `Sources/CloudflareKit/Analytics.swift`, `Allowances.swift`; `Tests/CloudflareKitTests/AnalyticsTests.swift`; fixtures `graphql-traffic-1d.json`, `graphql-workers.json`

**Interfaces:**
- Produces: `public enum UsageRange: String, CaseIterable, Sendable { case h24 = "24h", d7 = "7d", d30 = "30d" }`; `public struct TrafficPoint: Sendable, Equatable { date: Date; requests: Int; cachedRequests: Int; threats: Int }`; `public struct TrafficSummary: Sendable, Equatable { points: [TrafficPoint]; var totalRequests: Int { get }; var cacheHitRatio: Double { get }; var threats: Int { get } }`; `public struct Meter: Sendable, Equatable { label: String; used: Double; limit: Double; unit: String; var fraction: Double { get }; var isHot: Bool { get } }`; `public enum PlanAllowances { public static let free: [String: Double] }` keyed `workersRequestsPerDay`, `kvReadsPerDay`, `kvWritesPerDay`, `d1RowsReadPerDay`, `d1RowsWrittenPerDay`, `r2StorageGB`, `pagesBuildsPerMonth` with the Cloudflare Free plan values at implementation time (check the current limits docs and record the date in a code comment); `extension CFClient { public func traffic(zoneIDs: [String], range: UsageRange) async throws -> TrafficSummary; public func accountMeters(accountID: String) async throws -> [Meter] }`.

- [ ] **Step 1: Write failing tests:** `fractionClampsToOneAndIsHotAboveEightyFivePercent` (used 91000 of 100000 -> `isHot`, used 120000 -> fraction 1.0); `cacheHitRatioHandlesZeroRequests` (0 -> 0.0, no NaN); `h24UsesHourlyDatasetAndOthersDaily` (the query string for `.h24` contains `httpRequests1hGroups`, `.d7` and `.d30` contain `httpRequests1dGroups`); `trafficDecodesFixtureAndSumsTotals`; `trafficWithNoZonesReturnsEmptySummary` (Review Focus 2); `accountMetersBuildsOneMeterPerAllowance`.
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement.** Before writing the account queries, confirm dataset and field names (`workersInvocationsAdaptive`, `kvOperationsAdaptiveGroups`, `d1AnalyticsAdaptiveGroups`, `r2StorageAdaptiveGroups`) against Cloudflare's GraphQL schema docs (the Cloudflare MCP `docs`/`search` tools or `cloudflare.com` GraphQL introspection) and save one scrubbed real response as the fixture. A dataset the token cannot read yields `.permissionDenied`, which the UI turns into a prompt (Task 13).
- [ ] **Step 4: Run to confirm pass.**
- [ ] **Step 5: Commit.** `feat(kit): traffic analytics and plan allowance meters`

### Task 8: Settings model and Keychain

**Files:**
- Create: `Nephele/Settings/AppSettings.swift`, `Nephele/Settings/SettingsStore.swift`, `Nephele/Auth/TokenStore.swift`
- Test: `NepheleTests/SettingsTests.swift`, `NepheleTests/TokenStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct AppSettings: Codable, Equatable` with fields: `theme: ThemeChoice (.system/.light/.dark)`, `accentHex: String = "#F6821F"`, `density: Density (.compact/.comfortable)`, `radius: Double = 10`, `fontSize: Double = 14`, `fontDesign: FontChoice (.system/.rounded/.serif/.mono)`, `iconWeight: Double = 1.8`, `tintSidebar: Bool = true`, `sidebarIcons: Bool = false`, `highContrast: Bool`, `reduceMotion: Bool`, `landing: Route = .overview`, `nav: [NavEntry] (id: Route, visible: Bool)`, `overview: OverviewSections (stats, chart, alerts, domains: Bool)`, `notifications: NotificationPrefs (cert, origin, usage, deploy, security: Bool; pollMinutes: Int = 5)`, `openAtLogin: Bool`, `showMenuBar: Bool = true`. `enum Route: String, Codable, CaseIterable { overview, domains, alerts, usage, appearance, settings }`.
  - `@MainActor @Observable final class SettingsStore { var settings: AppSettings; init(defaults: UserDefaults = .standard); func exportJSON() -> String; func importJSON(_ text: String) throws; func reset() }` (persists to `UserDefaults` key `nephele.settings` on every change).
  - `struct TokenStore { init(service: String = "io.github.ol775.nephele"); func save(_ token: String) throws; func load() -> String?; func delete() }` (generic-password Keychain item, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).

- [ ] **Step 1: Write failing tests:** `settingsRoundTripThroughExportImport`; `importRejectsInvalidJSON` (throws, settings unchanged); `importAddsMissingNavEntries` (a JSON whose `nav` lacks `settings` gets it appended visible); `importIgnoresUnknownKeysAndFillsDefaults`; `appearanceAndSettingsCannotBeHidden` (setting `visible=false` for those two is coerced to true); `tokenSaveLoadDelete` and `tokenSaveOverwrites` (use `service: "io.github.ol775.nephele.tests.\(UUID())"` and delete in a `defer`); `tokenNeverStoredInUserDefaults` (after `save`, scanning `UserDefaults.standard.dictionaryRepresentation()` values for the token finds nothing).
- [ ] **Step 2: Run to confirm failure.** `xcodebuild test -scheme Nephele -destination 'platform=macOS' -only-testing:NepheleTests/SettingsTests`.
- [ ] **Step 3: Implement.** Use `JSONDecoder` with a custom `init(from:)` using `decodeIfPresent` and defaults so partial JSON imports work.
- [ ] **Step 4: Run to confirm pass.**
- [ ] **Step 5: Commit.** `feat(app): settings model, persistence and Keychain token store`

### Task 9: Design tokens and app shell

**Files:**
- Create: `Nephele/Theme/NepheleTheme.swift`, `Nephele/Shell/AppShell.swift`, `Nephele/Shell/Route+UI.swift`; modify `Nephele/NepheleApp.swift`
- Test: `NepheleTests/ThemeTests.swift`

**Interfaces:**
- Consumes: `SettingsStore`.
- Produces: `struct NepheleTheme { let accent: Color; let accentInk: Color; let radius: CGFloat; let pad: CGFloat; let rowPad: CGFloat; let fontDesign: Font.Design; let iconWeight: Font.Weight; init(_ s: AppSettings) }` injected with `.environment(\.nepheleTheme, ...)`; `static func readableInk(onHex: String) -> Color` (relative-luminance threshold 0.3: dark `#1A1100` above, white below); `Route.title: String`, `Route.symbol: String` (SF Symbols); `struct AppShell: View` (`NavigationSplitView`, sidebar built from `settings.nav` where `visible`, detail switch on selected `Route`, opens on `settings.landing`, applies `preferredColorScheme` from `settings.theme`, `.dynamicTypeSize` is not used, text size via `settings.fontSize`).

- [ ] **Step 1: Write failing tests:** `inkIsDarkOnOrangeAndWhiteOnNavy` (`#F6821F` -> dark, `#1F2A5C` -> white); `compactDensityHasSmallerPaddingThanComfortable`; `themeFollowsRadiusAndFontDesign`.
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement.** Each detail view is a placeholder `Text(route.title)` for now. Sidebar uses `Label(route.title, systemImage: route.symbol)`; the accent is applied with `.tint(theme.accent)`; "tint sidebar" mixes 5% accent into the sidebar background.
- [ ] **Step 4: Run to confirm pass; then `xcodebuild build` and launch the app once: the sidebar shows the six routes in the order from settings.**
- [ ] **Step 5: Commit.** `feat(app): design tokens and navigation shell`

### Task 10: Session, sign-in and Settings screen

**Files:**
- Create: `Nephele/Session/Session.swift`, `Nephele/Session/LoadState.swift`, `Nephele/Views/SignInView.swift`, `Nephele/Views/SettingsView.swift`
- Test: `NepheleTests/SessionTests.swift`

**Interfaces:**
- Consumes: `TokenStore`, `CFClient`, `CloudflareKitTesting.StubURLProtocol`.
- Produces: `enum LoadState<T: Sendable>: Sendable { case idle, loading, loaded(T), failed(CFError) }` (shared by every store); `@MainActor @Observable final class Session { enum State { case signedOut, verifying, ready }; var state: State; var accounts: [CFAccount]; var selectedAccountID: String?; var permissions: [PermissionStatus]; var client: CFClient?; init(tokenStore: TokenStore, makeClient: @escaping (String) -> CFClient); func restore() async; func signIn(token: String) async throws; func signOut(); func handle(_ error: CFError) }`; static `Session.isPlausibleToken(_:) -> Bool` (`^[A-Za-z0-9_-]{40}$`).

- [ ] **Step 1: Write failing tests:** `plausibleTokenRequires40AllowedCharacters`; `signInWithValidTokenStoresItAndBecomesReady` (stub verify 200, accounts 1, probes mixed); `signInWithInvalidTokenStaysSignedOutAndStoresNothing`; `restoreUsesStoredToken`; `unauthorizedErrorSignsOutAndClearsToken` (Review Focus 5: `handle(.unauthorized)` -> `state == .signedOut`, `TokenStore.load() == nil`); `permissionDeniedDoesNotSignOut` (Review Focus 1); `permissionsListSurfacesMissingOnes`.
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement.** `NepheleApp` shows `SignInView` when `state == .signedOut` and `AppShell` otherwise. `SignInView`: secure field, "Verify and save", inline error copy from `CFError.errorDescription`, plain explanation of the token permissions to create. `SettingsView` sections per the spec's "App Settings": account and token (masked `cf_••••` plus last four characters, replace, remove with a confirm naming "the API token"), permissions table with "N missing" note, notifications (five toggles, poll interval 1/5/15/30), general (open at login via `SMAppService.mainApp`, menu bar item toggle, "Deleting or overwriting anything asks you to confirm first" as static text), data (cache size and clear), keyboard shortcuts list, about (version from bundle, MIT, "not affiliated with Cloudflare" line).
- [ ] **Step 4: Run to confirm pass.** Then run the app and sign in with the owner's own scoped read-only token (entered by the owner; never in chat or files): the permissions table matches the token.
- [ ] **Step 5: Commit.** `feat(app): session, sign-in and Settings screen`

### Task 11: Overview, Domains and DNS

**Files:**
- Create: `Nephele/Domains/DomainsStore.swift`, `DNSStore.swift`, `Nephele/Views/OverviewView.swift`, `DomainsView.swift`, `DNSDetailView.swift`, `Nephele/Views/Components/` (`StatStrip.swift`, `StatusDot.swift`, `EmptyStateView.swift`, `PermissionPrompt.swift`, `AreaChart.swift`)
- Test: `NepheleTests/DomainsStoreTests.swift`, `NepheleTests/DNSStoreTests.swift`

**Interfaces:**
- Consumes: `Session.client`, `CFClient.zones()`, DNS API, `LoadState`, `DNSRecordDraft.validated(zone:)`.
- Produces: `@MainActor @Observable final class DomainsStore { var zones: LoadState<[Zone]>; init(session: Session, ttl: TimeInterval = 60); func load(force: Bool = false) async }`; `@MainActor @Observable final class DNSStore { var records: LoadState<[DNSRecord]>; var pendingDelete: DNSRecord?; var formError: String?; init(zone: Zone, session: Session); func load() async; func add(_ draft: DNSRecordDraft) async; func toggleProxy(_ record: DNSRecord) async; func requestDelete(_ record: DNSRecord); func confirmDelete() async; func cancelDelete() }`.

- [ ] **Step 1: Write failing tests:** `loadWithinTTLDoesNotRefetch` (second `load()` makes no request); `forceReloadRefetches`; `permissionDeniedBecomesFailedStateNotCrash` (Review Focus 1); `emptyZonesIsLoadedEmpty` (Review Focus 2); `invalidDraftSetsFormErrorAndSendsNothing` (no request recorded); `addRefreshesRecordList`; `deleteDoesNothingUntilConfirmed` (`requestDelete` -> `pendingDelete` set, zero DELETE requests; `confirmDelete` -> one DELETE, record removed; `cancelDelete` -> none); `toggleProxyIsRejectedForMX` (no request, `formError` set).
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement stores and views to match the mockup.** Overview: hero requests number (accent, large) with sparkline, three neutral supports (cache hit ratio, threats blocked, open alerts), range picker 24h/7d/30d, Swift Charts area chart with horizontal gridlines only, "Needs attention" list, domains table (`Table`) with status dot, plan and request bar. Domains: filter field, "Needs attention" filter, empty and no-match states. DNS detail: records table, proxy toggle, delete via confirmation dialog whose message names the record type and name and says it is live DNS, add form with inline validation. Every region has loading (skeleton), empty and failed states; `.permissionDenied` renders `PermissionPrompt("Zone: Read")`-style copy ("Your token can't read DNS records. Add DNS Read, then refresh.") (Review Focus 1, 2).
- [ ] **Step 4: Run to confirm pass.** Then manual check with the owner's token: Overview numbers load, DNS add/edit/delete work against a throwaway `example` record the owner creates, delete asks for confirmation.
- [ ] **Step 5: Commit.** `feat(app): overview, domains and DNS management`

### Task 12: Alerts, notifications and menu bar

**Files:**
- Create: `Nephele/Alerts/AlertsStore.swift`, `AlertPoller.swift`, `Notifier.swift`, `Nephele/Views/AlertsView.swift`, `Nephele/MenuBar/MenuBarContent.swift`; modify `NepheleApp.swift` (`MenuBarExtra`, shown when `settings.showMenuBar`)
- Test: `NepheleTests/AlertPollerTests.swift`

**Interfaces:**
- Consumes: `AlertDeduper`, `Session`, `SettingsStore`.
- Produces: `protocol Notifier: Sendable { func post(title: String, body: String) async }` (real implementation wraps `UNUserNotificationCenter`, asks authorisation on first need); `@MainActor @Observable final class AlertsStore { var policies: LoadState<[AlertPolicy]>; var events: LoadState<[AlertEvent]>; var acknowledged: Set<String>; var openCount: Int { get }; func load() async; func acknowledge(_ id: String) }` (acknowledged ids persisted in `UserDefaults`); `@MainActor final class AlertPoller { init(store: AlertsStore, session: Session, settings: SettingsStore, notifier: any Notifier); func start(); func stop(); func pollOnce() async }` (interval from `settings.notifications.pollMinutes`).

- [ ] **Step 1: Write failing tests:** `firstPollIsSilentlyPrimed` (existing events produce zero notifications); `newEventPostsExactlyOneNotification` (poll twice with the same new event -> one post) (Review Focus 5); `categoryToggleOffSuppressesNotification` (e.g. `cert` off, certificate event -> none, but still listed); `networkErrorKeepsLastEventsAndDoesNotNotify`; `rateLimitedPollKeepsLastEvents`; `unauthorizedPollSignsOutSession`; `acknowledgeLowersOpenCount`; `noAlertsIsLoadedEmpty` (Review Focus 2).
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement.** Alerts view: Open/All toggle, acknowledge button, "You're all clear" empty state, "Notification rules" opens the policies list. Menu bar content: open alert count and up to 5 domains with status dots, "Open Nephele" and "Settings". Poller runs only while signed in and stops on sign-out.
- [ ] **Step 4: Run to confirm pass.** Then manual: leave the app running with a 1-minute interval and confirm a fresh alert (or temporarily lowering a threshold in the owner's own account) produces one banner.
- [ ] **Step 5: Commit.** `feat(app): alerts, notifications and menu bar item`

### Task 13: Usage

**Files:**
- Create: `Nephele/Usage/UsageStore.swift`, `Nephele/Views/UsageView.swift`
- Test: `NepheleTests/UsageStoreTests.swift`

**Interfaces:**
- Consumes: `CFClient.traffic`, `accountMeters`, `Meter`, `UsageRange`.
- Produces: `@MainActor @Observable final class UsageStore { var range: UsageRange; var traffic: LoadState<TrafficSummary>; var meters: LoadState<[Meter]>; init(session: Session, domains: DomainsStore); func load() async; func setRange(_ r: UsageRange) async }`.

- [ ] **Step 1: Write failing tests:** `changingRangeRefetchesTraffic`; `meterDatasetDeniedShowsPermissionStateOthersStillLoad` (traffic ok, meters `.permissionDenied` -> traffic `.loaded`, meters `.failed(.permissionDenied)`) (Review Focus 1); `noZonesGivesEmptyTrafficNotError` (Review Focus 2).
- [ ] **Step 2: Run to confirm failure.**
- [ ] **Step 3: Implement.** View: area chart, "This month" estimated overage ($0.00 until Cloudflare exposes it; show "Not available" if no source), allowance meters with the hot colour above 85%.
- [ ] **Step 4: Run to confirm pass.**
- [ ] **Step 5: Commit.** `feat(app): usage screen`

### Task 14: Appearance screen

**Files:**
- Create: `Nephele/Views/AppearanceView.swift`

**Interfaces:**
- Consumes: `SettingsStore` (all logic and tests already exist from Task 8; this task is UI only).

- [ ] **Step 1: Build the screen** with a grouped `Form` bound to `SettingsStore.settings`: theme (segmented), accent (seven presets from the mockup plus `ColorPicker`, showing a checkmark with `readableInk`), tinted sidebar, corner radius slider, icon weight (light 1.4 / regular 1.8 / bold 2.3), typeface, text size, density, sidebar style (icons only or with labels), "Open on" picker, sidebar items (visibility toggle with up/down reordering; Appearance and Settings locked on), Overview sections toggles, increased contrast, reduce motion (also respects the system setting), backup (text editor with export JSON, "Apply pasted settings" with inline error "That isn't valid settings JSON.", "Reset to Cloudflare defaults" with a confirmation).
- [ ] **Step 2: Verify manually.** Change each control and see the whole app respond live; quit and relaunch and confirm everything persisted; export, change things, re-import, confirm restore; invalid JSON shows the inline error and changes nothing.
- [ ] **Step 3: Commit.** `feat(app): appearance screen`

### Task 15: App icon and release hygiene

**Files:**
- Create: `Nephele/Assets.xcassets/AppIcon.appiconset/` (PNGs at 16, 32, 64, 128, 256, 512, 1024 plus `Contents.json`), `scripts/make-icons.sh`
- Modify: `README.md`, `project.yml` (asset catalogue and `ASSETCATALOG_COMPILER_APPICON_NAME`)

**Interfaces:**
- Consumes: `assets/logo.svg` (Cloud cleft, 1024 viewBox).

- [ ] **Step 1: Write `scripts/make-icons.sh`** that renders `assets/logo.svg` to a 1024 PNG (`qlmanage -t -s 1024 -o <tmp> assets/logo.svg`), then derives each size with `sips -z`, and writes the PNGs and `Contents.json`. The script exits non-zero if the SVG is missing.
- [ ] **Step 2: Run it, rebuild, launch.** The Dock and the app switcher show the Cloud cleft icon; zoom in on the 16 and 32 px renders and note whether the seam stays legible (record the finding in the README "Known issues"; a hand-tuned 16 px variant is a follow-up, as the logo notes say).
- [ ] **Step 3: Update README** with prerequisites (Xcode 26+, XcodeGen), build/run/test commands, token permissions to create (read-only first), the privacy statement (no analytics; token in Keychain), and the licence.
- [ ] **Step 4: Final verification.** `swift test --package-path Packages/CloudflareKit` and `xcodebuild test -scheme Nephele -destination 'platform=macOS'` both pass; run `git grep -iE "(api[_-]?token|bearer) [A-Za-z0-9_-]{30,}"` and confirm no real secrets; confirm `git log --format='%an <%ae>'` shows only `Ol775 <Ol775@users.noreply.github.com>`.
- [ ] **Step 5: Commit.** `feat: app icon, README and release hygiene`

---

## Self-review notes

- **Spec coverage:** token entry, validation and Keychain (8, 10); zones overview (4, 11); DNS list/add/edit/delete with confirm (5, 11); alerts (6, 12); usage (7, 13); menu bar item and notifications (12); app Settings (10); Appearance and personalisation (8, 14); design tokens and look (9); icon (15); empty, loading and failed states and permission prompts (11, 12, 13). Phases 2 to 4 are intentionally out of scope.
- **Not in this plan, by decision:** sidebar-right option, hand-tuned 16 px icon, notarised DMG or Homebrew cask (set up before the public flip, own plan), the name and logo trademark searches (owner action before going public).
- **Type consistency:** `LoadState` (Task 10) is the only state type used by Tasks 11 to 13; `Session.client` (Task 10) is the only source of `CFClient` for stores; `CFError` cases are those defined in Task 2.
