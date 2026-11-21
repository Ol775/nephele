import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

actor FakeNotifier: Notifier {
    private(set) var posts: [String] = []
    func post(title: String, body: String) async { posts.append(title) }
    var count: Int { posts.count }
}

final class HistoryFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [(id: String, type: String)] = []
    private var _status = 200
    private var _offline = false
    var events: [(id: String, type: String)] { get { lock.withLock { _events } } set { lock.withLock { _events = newValue } } }
    var status: Int { get { lock.withLock { _status } } set { lock.withLock { _status = newValue } } }
    var offline: Bool { get { lock.withLock { _offline } } set { lock.withLock { _offline = newValue } } }

    func handle(_ req: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard req.url!.path.hasSuffix("/alerting/v3/history") else { return TestAPI.base(req) }
        if offline { throw URLError(.notConnectedToInternet) }
        if status != 200 { return (StubURLProtocol.response(req.url!, status: status, headers: ["Retry-After": "0"]), Data("{\"success\":false,\"errors\":[{\"code\":1000,\"message\":\"nope\"}],\"result\":null}".utf8)) }
        let rows = events.map { "{\"id\":\"\($0.id)\",\"name\":\"Alert \($0.id)\",\"alert_type\":\"\($0.type)\",\"policy_id\":\"p\",\"sent\":\"2026-11-21T10:00:00Z\"}" }.joined(separator: ",")
        return TestAPI.reply(req, TestAPI.ok("[\(rows)]"))
    }
}

@MainActor
@Suite struct AlertPollerTests {
    struct Rig { let poller: AlertPoller; let store: AlertsStore; let session: Session; let settings: SettingsStore; let notifier: FakeNotifier; let feed: HistoryFeed }

    func rig(_ events: [(String, String)] = []) async throws -> Rig {
        let feed = HistoryFeed()
        feed.events = events.map { (id: $0.0, type: $0.1) }
        let stub = StubServer { try feed.handle($0) }
        let session = try await TestAPI.readySession(stub)
        let defaults = UserDefaults(suiteName: "nephele.tests.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        let store = AlertsStore(session: session, defaults: defaults)
        let notifier = FakeNotifier()
        let poller = AlertPoller(store: store, session: session, settings: settings, notifier: notifier, defaults: defaults)
        return Rig(poller: poller, store: store, session: session, settings: settings, notifier: notifier, feed: feed)
    }

    @Test func firstPollIsSilentlyPrimed() async throws {
        let r = try await rig([("a", "incident_alert"), ("b", "http_alert_origin_error")])
        await r.poller.pollOnce()
        #expect(await r.notifier.count == 0)
        #expect(r.store.events.value?.count == 2)
    }

    @Test func newEventPostsExactlyOneNotification() async throws {
        let r = try await rig([("a", "incident_alert")])
        await r.poller.pollOnce()
        r.feed.events = [(id: "a", type: "incident_alert"), (id: "b", type: "http_alert_origin_error")]
        await r.poller.pollOnce()
        await r.poller.pollOnce()
        #expect(await r.notifier.count == 1)
    }

    @Test func categoryToggleOffSuppressesNotificationButStillListsIt() async throws {
        let r = try await rig([("a", "incident_alert")])
        r.settings.update { $0.notifications.cert = false }
        await r.poller.pollOnce()
        r.feed.events = [(id: "a", type: "incident_alert"), (id: "c", type: "universal_ssl_event_type")]
        await r.poller.pollOnce()
        #expect(await r.notifier.count == 0)
        #expect(r.store.events.value?.map(\.id) == ["a", "c"])
    }

    @Test func networkErrorKeepsLastEventsAndDoesNotNotify() async throws {
        let r = try await rig([("a", "incident_alert")])
        await r.poller.pollOnce()
        r.feed.offline = true
        await r.poller.pollOnce()
        #expect(r.store.events.value?.map(\.id) == ["a"])
        #expect(r.store.lastError != nil)
        #expect(await r.notifier.count == 0)
    }

    @Test func rateLimitedPollKeepsLastEvents() async throws {
        let r = try await rig([("a", "incident_alert")])
        await r.poller.pollOnce()
        r.feed.status = 429
        await r.poller.pollOnce()
        #expect(r.store.events.value?.map(\.id) == ["a"])
        #expect(r.store.lastError == .rateLimited(retryAfter: 0))
    }

    @Test func unauthorizedPollSignsOutSession() async throws {
        let r = try await rig([("a", "incident_alert")])
        await r.poller.pollOnce()
        r.feed.status = 401
        await r.poller.pollOnce()
        #expect(r.session.state == .signedOut)
    }

    @Test func acknowledgeLowersOpenCountAndPersists() async throws {
        let r = try await rig([("a", "incident_alert"), ("b", "incident_alert")])
        await r.store.load()
        #expect(r.store.openCount == 2)
        r.store.acknowledge("a")
        #expect(r.store.openCount == 1)
    }

    @Test func noAlertsIsLoadedEmpty() async throws {
        let r = try await rig([])
        await r.store.load()
        #expect(r.store.events.value?.isEmpty == true)
        #expect(r.store.openCount == 0)
    }

    @Test func switchingAccountPrimesTheNewAccountSilently() async throws {
        let r = try await rig([("a", "incident_alert")])
        await r.poller.pollOnce()
        r.session.selectAccount("acc2")
        r.feed.events = [(id: "x", type: "http_alert_origin_error"), (id: "y", type: "universal_ssl_event_type")]
        await r.poller.pollOnce()
        #expect(await r.notifier.count == 0)
        r.feed.events.append((id: "z", type: "http_alert_origin_error"))
        await r.poller.pollOnce()
        #expect(await r.notifier.count == 1)
    }

    @Test func resetClearsLoadedAlerts() async throws {
        let r = try await rig([("a", "incident_alert")])
        await r.store.load()
        r.store.reset()
        #expect(r.store.events.value == nil)
        #expect(r.store.policies.value == nil)
    }

    @Test func alertTypesMapToNotificationCategories() {
        #expect(AlertCategory.of(alertType: "universal_ssl_event_type") == .cert)
        #expect(AlertCategory.of(alertType: "http_alert_origin_error") == .origin)
        #expect(AlertCategory.of(alertType: "dos_attack_l7") == .security)
        #expect(AlertCategory.of(alertType: "incident_alert") == nil)
    }
}
