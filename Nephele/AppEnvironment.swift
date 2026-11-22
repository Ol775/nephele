import Foundation

enum AppEnvironment {
    /// True when the app is the host process for unit tests: it must not touch the real Keychain or account.
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
    /// `Nephele --demo` runs against built-in sample data and never touches the Keychain or the network.
    static var isDemo: Bool { CommandLine.arguments.contains("--demo") }
}
