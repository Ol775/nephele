import SwiftUI
import AppKit
import CloudflareKit

/// `Nephele --demo --snapshot=DIR` writes PNGs of every screen to DIR and quits. Used to make the README images.
/// It captures the app's own window, which needs no screen-recording permission.
@MainActor
enum DemoSnapshots {
    static var directory: URL? {
        CommandLine.arguments.first { $0.hasPrefix("--snapshot=") }.map { URL(fileURLWithPath: String($0.dropFirst(11))) }
    }

    static func run(into dir: URL, navigator: Navigator, session: Session, zone: Zone, routes: [Route], zoneScreens: [String]) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        while session.state != .ready { try? await Task.sleep(for: .milliseconds(200)) }
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow() {
            window.setContentSize(NSSize(width: 1180, height: 760)); window.center(); window.makeKeyAndOrderFront(nil)
        }
        try? await Task.sleep(for: .seconds(2))
        let only = CommandLine.arguments.first { $0.hasPrefix("--only=") }.map { Set($0.dropFirst(7).split(separator: ",").map(String.init)) }
        for route in routes where only?.contains(route.rawValue) ?? true {
            navigator.selection = route
            try? await Task.sleep(for: .seconds(3))
            write(to: dir.appendingPathComponent("\(route.rawValue).png"))
        }
        for screen in zoneScreens where only?.contains(screen) ?? true {
            navigator.selection = .overview
            try? await Task.sleep(for: .seconds(1))
            navigator.zoneScreen = screen == "dns" ? nil : screen
            navigator.selection = .domains
            try? await Task.sleep(for: .seconds(1))
            navigator.openZone = zone
            try? await Task.sleep(for: .seconds(3))
            write(to: dir.appendingPathComponent("\(screen).png"))
            navigator.openZone = nil
        }
        NSApp.terminate(nil)
    }

    private static func mainWindow() -> NSWindow? { NSApp.windows.first { $0.isVisible && $0.frame.width > 400 } }

    /// CGWindowListCreateImage is marked unavailable to Swift on current SDKs but still works for a process's own windows.
    private static func write(to url: URL) {
        guard let window = mainWindow() else { return }
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let create = unsafeBitCast(sym, to: Fn.self)
        // option 8 = this window only, image option 8 = best resolution (shadow and frame included)
        guard let image = create(.null, 8, UInt32(window.windowNumber), 8)?.takeRetainedValue() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
