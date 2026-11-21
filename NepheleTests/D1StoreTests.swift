import Testing
import Foundation
import CloudflareKit
import CloudflareKitTesting
@testable import Nephele

@MainActor
@Suite struct D1StoreTests {
    nonisolated static let dbs = "[{\"uuid\":\"db-2\",\"name\":\"logs\"},{\"uuid\":\"db-1\",\"name\":\"app\"}]"
    nonisolated static func raw(cols: [String] = ["name"], rows: String = "[[\"users\"],[\"posts\"]]") -> String {
        "[{\"results\":{\"columns\":[\(cols.map { "\"\($0)\"" }.joined(separator: ","))],\"rows\":\(rows)},\"meta\":{\"rows_read\":2,\"rows_written\":0,\"duration\":0.1}}]"
    }

    func make(denyWrites: Bool = false) async throws -> (D1Store, StubServer) {
        let stub = StubServer { req in
            let p = req.url!.path
            let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
            if p.hasSuffix("/raw") {
                if denyWrites && !body.contains("sqlite_master") && !body.lowercased().contains("select 1") { return TestAPI.reply(req, TestAPI.forbiddenBody, status: 403) }
                return TestAPI.reply(req, TestAPI.ok(Self.raw()))
            }
            if req.httpMethod == "DELETE" { return TestAPI.reply(req, TestAPI.ok("null")) }
            if req.httpMethod == "POST" && p.hasSuffix("/d1/database") { return TestAPI.reply(req, TestAPI.ok("{\"uuid\":\"db-3\",\"name\":\"fresh\"}")) }
            if p.hasSuffix("/d1/database") { return TestAPI.reply(req, TestAPI.ok(Self.dbs)) }
            return TestAPI.base(req)
        }
        let store = D1Store(session: try await TestAPI.readySession(stub))
        await store.load()
        return (store, stub)
    }

    func queries(_ stub: StubServer) -> [String] {
        stub.recorded.filter { $0.request.url!.path.hasSuffix("/raw") }.compactMap { rec in
            rec.body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0)["sql"]?.stringValue }
        }
    }

    @Test func loadsDatabasesSortedAndSelectingListsTables() async throws {
        let (store, _) = try await make()
        #expect(store.databases.value?.map(\.name) == ["app", "logs"])
        await store.select(store.databases.value?.first)
        #expect(store.tables == ["users", "posts"])
    }

    @Test func readOnlySqlRunsWithoutConfirmation() async throws {
        let (store, stub) = try await make()
        await store.select(store.databases.value?.first)
        store.sql = "SELECT * FROM users"
        await store.run()
        #expect(store.confirm.pending == nil)
        #expect(queries(stub).contains("SELECT * FROM users"))
        #expect(store.results.value?.first?.rowsRead == 2)
    }

    @Test func writeSqlWaitsForConfirmationThenRunsOnce() async throws {
        let (store, stub) = try await make()
        await store.select(store.databases.value?.first)
        store.sql = "DELETE FROM users"
        await store.run()
        #expect(!queries(stub).contains("DELETE FROM users"))
        let pending = try #require(store.confirm.pending)
        #expect(pending.message(database: "app").contains("app"))
        await store.confirmWrite(pending)
        await store.confirmWrite(pending)
        #expect(queries(stub).filter { $0 == "DELETE FROM users" }.count == 1)
    }

    @Test func cancelledWriteNeverRuns() async throws {
        let (store, stub) = try await make()
        await store.select(store.databases.value?.first)
        store.sql = "DROP TABLE users"
        await store.run()
        let pending = try #require(store.confirm.pending)
        store.confirm.cancel()
        await store.confirmWrite(pending)
        #expect(!queries(stub).contains("DROP TABLE users"))
    }

    @Test func forbiddenWriteDisablesWritesButNotReads() async throws {
        let (store, _) = try await make(denyWrites: true)
        await store.select(store.databases.value?.first)
        store.sql = "INSERT INTO users VALUES (1)"
        await store.run()
        await store.confirmWrite(try #require(store.confirm.pending))
        #expect(store.canWrite == false)
        #expect(store.formError?.contains("D1 Edit") == true)
        store.sql = "SELECT 1"
        await store.run()
        #expect(store.results.value != nil)
    }

    @Test func createAndDeleteRespectNamesAndTypedConfirmation() async throws {
        let (store, stub) = try await make()
        await store.create("bad name")
        #expect(store.formError != nil)
        await store.create("fresh")
        #expect(store.databases.value?.map(\.name).contains("fresh") == true)
        let db = try #require(store.databases.value?.first { $0.name == "app" })
        let before = stub.recorded.count
        await store.delete(db, typedName: "ap")
        #expect(store.formError != nil && stub.recorded.count == before)
        await store.delete(db, typedName: "app")
        #expect(store.databases.value?.map(\.name).contains("app") == false)
    }
}
