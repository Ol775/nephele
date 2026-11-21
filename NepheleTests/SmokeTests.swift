import Testing
import Foundation

@Suite struct SmokeTests {
    @Test func appBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "io.github.ol775.nephele")
    }
}
