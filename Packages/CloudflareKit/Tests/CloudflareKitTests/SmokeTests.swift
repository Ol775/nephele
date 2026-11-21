import Testing
@testable import CloudflareKit

@Suite struct SmokeTests {
    @Test func versionIsSet() { #expect(CloudflareKit.version == "0.1.0") }
}
