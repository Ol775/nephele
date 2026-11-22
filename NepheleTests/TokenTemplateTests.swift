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

    @Test func fullAccessAddsZeroTrustEditAndListsEveryByHandPermission() throws {
        let full = try permissions(.full)
        #expect(full.first { $0["key"] == "teams" }?["type"] == "edit" && full.first { $0["key"] == "cache" }?["type"] == "purge")
        #expect(!(try permissions(.readAndEdit)).contains { $0["key"] == "teams" })
        for name in ["Email Routing Rules", "Email Routing Addresses", "Zone WAF", "Turnstile Sites", "Cloudflare Tunnel", "Access: Service Tokens", "Notifications"] {
            #expect(TokenAccess.full.byHand.contains(name))
        }
        #expect(TokenAccess.readOnly.byHand.contains("Read") && !TokenAccess.readOnly.byHand.contains("Edit"))
        #expect(TokenAccess.full.byHand.contains("Edit"))
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
