import Testing
@testable import Nephele

@Suite struct AppEnvironmentTests {
    @Test func theAppKnowsItIsRunningUnderTests() {
        #expect(AppEnvironment.isRunningTests)
    }
}
