import Testing
import Foundation
import CloudflareKitTesting
@testable import CloudflareKit

@Suite struct D1Tests {
    func client(_ stub: StubServer) -> CFClient { CFClient(token: "t", session: stub.session) }

    @Test func databasesDecode() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("d1-databases")) }
        let list = try await client(stub).d1Databases(accountID: "acc1")
        #expect(list.map(\.name) == ["app-db", "logs"])
        #expect(list[0].id == "db-1")
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/accounts/acc1/d1/database")
    }

    @Test func queryUsesRawEndpointAndKeepsColumnOrderAndRendersCells() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), fixture("d1-raw")) }
        let results = try await client(stub).queryD1(accountID: "acc1", database: "db-1", sql: "SELECT * FROM t")
        let r = try #require(results.first)
        #expect(r.columns == ["id", "name", "score"])
        #expect(r.rows == [["1", "ada", "9.5"], ["2", "NULL", "true"], ["3", "x\"y", "{\"a\":1}"]])
        #expect(r.rowsRead == 3 && r.rowsWritten == 0 && r.duration == 0.42)
        let rec = try #require(stub.recorded.first)
        #expect(rec.request.url?.path == "/client/v4/accounts/acc1/d1/database/db-1/raw")
        let raw = try #require(rec.body)
        #expect(try JSONDecoder().decode(JSONValue.self, from: raw)["sql"] == .string("SELECT * FROM t"))
    }

    @Test func readOnlyClassification() {
        for ok in ["SELECT 1", "  select * from t;", "WITH a AS (SELECT 1) SELECT * FROM a", "EXPLAIN SELECT 1", "PRAGMA table_info(t)",
                   "-- hi\nSELECT 1", "/* c */ SELECT 1; SELECT 2"] { #expect(D1SQL.isReadOnly(ok), "\(ok)") }
        for bad in ["DROP TABLE t", "delete from t", "UPDATE t SET a=1", "INSERT INTO t VALUES (1)", "CREATE TABLE t(a)", "ALTER TABLE t ADD b",
                    "REPLACE INTO t VALUES (1)", "PRAGMA foreign_keys = ON", "SELECT 1; DELETE FROM t", "WITH a AS (SELECT 1) DELETE FROM t",
                    "ATTACH DATABASE 'x' AS y", "VACUUM", "", "   ", "/* only a comment */"] { #expect(!D1SQL.isReadOnly(bad), "\(bad)") }
    }

    @Test func createValidatesNameThenPosts() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":{\"uuid\":\"db-9\",\"name\":\"fresh\"}}".utf8)) }
        let db = try await client(stub).createD1Database(accountID: "acc1", name: "fresh")
        #expect(db.id == "db-9")
        let c = client(stub)
        await #expect(throws: WorkerValidationError.invalidName) { _ = try await c.createD1Database(accountID: "acc1", name: "bad name") }
        #expect(stub.recorded.count == 1)
    }

    @Test func deleteUsesDelete() async throws {
        let stub = StubServer { req in (StubURLProtocol.response(req.url!), Data("{\"success\":true,\"errors\":[],\"result\":null}".utf8)) }
        try await client(stub).deleteD1Database(accountID: "acc1", database: "db-1")
        #expect(stub.recorded.first?.request.httpMethod == "DELETE")
        #expect(stub.recorded.first?.request.url?.path == "/client/v4/accounts/acc1/d1/database/db-1")
    }

    @Test func quotesCannotHideAWriteFromTheClassifier() {
        for bad in ["SELECT '--'; DROP TABLE t", "SELECT 'it''s'; DROP TABLE t", "SELECT \"a--b\" FROM t; DELETE FROM t", "SELECT `x/*` FROM t; DROP TABLE t; --*/",
                    "SELECT 'unclosed", "SELECT 1 /* unclosed; DROP TABLE t", "PRAGMA user_version(5)", "PRAGMA writable_schema", "SELECT [a FROM t; DROP TABLE t"] {
            #expect(!D1SQL.isReadOnly(bad), "\(bad)")
        }
        for ok in ["SELECT 'a;b' FROM t", "SELECT 'delete me'", "SELECT [x;y] FROM t", "SELECT \"weird;name\" FROM t", "PRAGMA table_info(t)", "PRAGMA index_list(t)", "SELECT 'it''s'"] {
            #expect(D1SQL.isReadOnly(ok), "\(ok)")
        }
    }

    @Test func identifiersAreQuotedWithDoubledQuotes() {
        #expect(D1SQL.quoteIdentifier("users") == "\"users\"")
        #expect(D1SQL.quoteIdentifier("we\"ird; DROP TABLE t") == "\"we\"\"ird; DROP TABLE t\"")
        #expect(D1SQL.isReadOnly("SELECT * FROM \(D1SQL.quoteIdentifier("we\"ird; DROP TABLE t")) LIMIT 100;"))
    }
}
