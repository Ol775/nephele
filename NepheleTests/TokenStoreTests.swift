import Testing
import Foundation
@testable import Nephele

@Suite(.serialized) struct TokenStoreTests {
    func store() -> TokenStore { TokenStore(service: "io.github.ol775.nephele.tests.\(UUID().uuidString)") }

    @Test func tokenSaveLoadDelete() throws {
        let s = store()
        defer { s.delete() }
        #expect(s.load() == nil)
        try s.save("abc123")
        #expect(s.load() == "abc123")
        s.delete()
        #expect(s.load() == nil)
    }

    @Test func tokenSaveOverwrites() throws {
        let s = store()
        defer { s.delete() }
        try s.save("first")
        try s.save("second")
        #expect(s.load() == "second")
    }

    @Test func tokenNeverStoredInUserDefaults() throws {
        let s = store()
        defer { s.delete() }
        let secret = "tok_NEVER_IN_DEFAULTS_\(UUID().uuidString)"
        try s.save(secret)
        let all = String(describing: UserDefaults.standard.dictionaryRepresentation())
        #expect(!all.contains(secret))
    }
}
