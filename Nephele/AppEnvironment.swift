import Foundation

enum AppEnvironment {
    /// True when the app is the host process for unit tests: it must not touch the real Keychain or account.
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
}
