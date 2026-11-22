import Testing
import Foundation
@testable import Nephele

@Suite struct TokenTemplateTests {
    func permissions(_ access: TokenAccess) throws -> [[String: String]] {
        let comps = try #require(URLComponents(url: access.createURL, resolvingAgainstBaseURL: false))
        let json = try #require(comps.queryItems?.first { $0.name == "permissionGroupKeys" }?.value)
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]])
    }

    @Test func readOnlyAsksOnlyForReadPermissions() throws {
        let perms = try permissions(.readOnly)
        #expect(!perms.isEmpty && perms.allSatisfy { $0["type"] == "read" })
        let keys = Set(perms.compactMap { $0["key"] })
        #expect(["zone", "dns", "account_analytics", "account_settings"].allSatisfy(keys.contains))
    }

    @Test func editAddsEditAndPurgeForTheSameAreas() throws {
        let read = Set(try permissions(.readOnly).compactMap { $0["key"] })
        let edit = try permissions(.readAndEdit)
        #expect(Set(edit.compactMap { $0["key"] }) == read.union(["cache"]))
        #expect(edit.first { $0["key"] == "dns" }?["type"] == "edit")
        #expect(edit.first { $0["key"] == "cache" }?["type"] == "purge")
        #expect(edit.first { $0["key"] == "account_analytics" }?["type"] == "read")
    }

    @Test func urlTargetsTheDashboardAndNamesTheToken() throws {
        for access in TokenAccess.allCases {
            let comps = try #require(URLComponents(url: access.createURL, resolvingAgainstBaseURL: false))
            #expect(comps.host == "dash.cloudflare.com" && comps.path == "/profile/api-tokens")
            let names = comps.queryItems?.filter { $0.name == "accountId" || $0.name == "zoneId" }.compactMap(\.value)
            #expect(names == ["*", "all"])
            #expect(comps.queryItems?.first { $0.name == "name" }?.value?.hasPrefix("Nephele") == true)
        }
    }
}
