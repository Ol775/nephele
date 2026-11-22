import AppKit
import CryptoKit
import Observation

// Updates come only from this repository's GitHub releases and install only if the Ed25519 signature made offline with
// the release key verifies (private key: ~/.config/nephele/signing.key, never committed). Same trust model as Task Manager
// and Claude Usage. See SECURITY.md.

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
}

struct UpdateInfo: Sendable, Equatable {
    let version: String
    let notes: [String]
    var dmgURL: URL?
    var sha256: String?
    var sigURL: URL?
}

enum UpdateStatus: Sendable, Equatable {
    case idle, checking, upToDate
    case available(UpdateInfo)
    case installing(String, Double)
    case failed(String)
}

private func versionParts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 } }

/// True when version `a` is newer than `b` ("major.minor.patch").
func isNewer(_ a: String, than b: String) -> Bool {
    let x = versionParts(a), y = versionParts(b)
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p > q }
    }
    return false
}

enum Updater {
    static let repo = "Ol775/nephele"
    static let bundleID = "io.github.ol775.nephele"
    static let appName = "Nephele"
    static let publicKey = "o6G6dgMCNQ3Hb2Pphohg4Is/QZitntyKGs4+wxj8HtM="

    static func isPlainVersion(_ v: String) -> Bool {
        v.range(of: #"^\d{1,4}\.\d{1,4}\.\d{1,4}$"#, options: .regularExpression) != nil
    }

    /// What the release key signs: label + version + disk image bytes, so an older signed image can't pass as a newer one.
    static func signedMessage(version: String, dmg: Data) -> Data { Data("nephele-update\nv\(version)\n".utf8) + dmg }

    static func isAllowedRedirectHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return h == "github.com" || h.hasSuffix(".githubusercontent.com")
    }

    /// Only this repository's release downloads on github.com: https, no port or credentials, no query, and no path tricks
    /// (".." or empty segments) that could climb out of /releases/download/.
    static func isTrustedAsset(_ u: URL) -> Bool {
        guard u.scheme == "https", u.host == "github.com", u.port == nil, u.user == nil, u.password == nil,
              u.query == nil, u.fragment == nil else { return false }
        let parts = u.path.split(separator: "/", omittingEmptySubsequences: false)
        return u.path.hasPrefix("/\(repo)/releases/download/") && !parts.dropFirst().contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    static func verifySignature(_ data: Data, base64Signature: String, publicKey key: String = Updater.publicKey) -> Bool {
        guard let k = Data(base64Encoded: key), let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: k),
              let sig = Data(base64Encoded: base64Signature.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return pub.isValidSignature(sig, for: data)
    }

    /// Follows redirects only to GitHub hosts, caps the download size and records the finished file.
    private final class Downloader: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
        static let maxBytes: Int64 = 100_000_000
        let onProgress: @Sendable (Double) -> Void
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _location: URL?, _status = 0
        var location: URL? { lock.withLock { _location } }
        var status: Int { lock.withLock { _status } }
        init(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) { self.onProgress = onProgress }
        func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest req: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(req.url?.scheme == "https" && Updater.isAllowedRedirectHost(req.url?.host) ? req : nil)
        }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
            if w > Self.maxBytes || e > Self.maxBytes { t.cancel(); return }
            if e > 0 { onProgress(min(1, Double(w) / Double(e))) }
        }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
            let keep = FileManager.default.temporaryDirectory.appendingPathComponent("nephele-\(UUID().uuidString)")
            let moved = (try? FileManager.default.moveItem(at: loc, to: keep)) != nil
            lock.withLock { _status = (t.response as? HTTPURLResponse)?.statusCode ?? 0; _location = moved ? keep : nil }
        }
        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { done.signal() }
    }

    private final class Box: @unchecked Sendable { var data: Data? }

    nonisolated private static func fetchData(_ url: URL, timeout: TimeInterval, accept: String? = nil) -> Data? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: Downloader(), delegateQueue: nil)
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        let sem = DispatchSemaphore(value: 0)
        let box = Box()
        session.dataTask(with: req) { d, r, _ in
            if (r as? HTTPURLResponse)?.statusCode == 200, let d, d.count < 1_000_000 { box.data = d }
            sem.signal()
        }.resume()
        sem.wait(); session.finishTasksAndInvalidate()
        return box.data
    }

    /// Blocking: call from a background task.
    nonisolated static func check(installed: String = AppInfo.version) -> UpdateStatus {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest"),
              let data = fetchData(url, timeout: 15, accept: "application/vnd.github+json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            return .failed("Couldn\u{2019}t find a release on GitHub. Check your connection and try again.")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isPlainVersion(version) else { return .failed("Unexpected version number on GitHub.") }
        guard isNewer(version, than: installed) else { return .upToDate }

        let assets = json["assets"] as? [[String: Any]] ?? []
        func asset(_ name: String) -> URL? {
            (assets.first { $0["name"] as? String == name }?["browser_download_url"] as? String)
                .flatMap(URL.init(string:)).flatMap { isTrustedAsset($0) ? $0 : nil }
        }
        let dmgName = assets.compactMap { $0["name"] as? String }.first { $0.hasSuffix(".dmg") } ?? ""
        let sha = asset(dmgName + ".sha256").flatMap { fetchData($0, timeout: 20) }.flatMap { String(data: $0, encoding: .utf8) }?
            .split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map { String($0).lowercased() }
        let notes = (json["body"] as? String ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return .available(UpdateInfo(version: version, notes: notes, dmgURL: asset(dmgName), sha256: sha, sigURL: asset(dmgName + ".sig2")))
    }

    // MARK: Installing

    @discardableResult
    nonisolated private static func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    nonisolated private static var cachesDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Nephele-updates")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }

    nonisolated private static func sha256Hex(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    struct Prepared: Sendable { var app: URL?, hash: String?, error: String? }

    /// Downloads and checks the release; installs nothing unless the signature, checksum, bundle id, version and code
    /// signature all pass. Blocking: call from a background task.
    nonisolated static func prepare(_ info: UpdateInfo, progress: @escaping @Sendable (String, Double) -> Void) -> Prepared {
        let fm = FileManager.default
        guard let dmgURL = info.dmgURL, isTrustedAsset(dmgURL), let want = info.sha256, let sigURL = info.sigURL else {
            return Prepared(error: "This release isn\u{2019}t signed, so it won\u{2019}t be installed automatically.")
        }
        let root = cachesDir.appendingPathComponent("update-\(Int(Date().timeIntervalSince1970))")
        guard (try? fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil else {
            return Prepared(error: "Couldn\u{2019}t create a work folder.")
        }
        func fail(_ m: String) -> Prepared { try? fm.removeItem(at: root); return Prepared(error: m) }

        progress("Downloading version \(info.version)\u{2026}", 0)
        let dl = Downloader { progress("Downloading version \(info.version)\u{2026}", $0 * 0.8) }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: dl, delegateQueue: nil)
        session.downloadTask(with: URLRequest(url: dmgURL, timeoutInterval: 60)).resume()
        dl.done.wait(); session.finishTasksAndInvalidate()
        guard dl.status == 200, let tmp = dl.location else { return fail("Couldn\u{2019}t download the update.") }
        let dmg = root.appendingPathComponent("update.dmg")
        guard (try? fm.moveItem(at: tmp, to: dmg)) != nil, let dmgData = try? Data(contentsOf: dmg, options: .alwaysMapped) else {
            return fail("Couldn\u{2019}t read the download.")
        }

        progress("Verifying\u{2026}", 0.85)
        guard let sigData = fetchData(sigURL, timeout: 20), let sig = String(data: sigData, encoding: .utf8),
              verifySignature(signedMessage(version: info.version, dmg: dmgData), base64Signature: sig) else {
            return fail("The download\u{2019}s signature didn\u{2019}t check out, so it was discarded.")
        }
        guard sha256Hex(dmgData) == want else { return fail("The download didn\u{2019}t match its checksum, so it was discarded.") }

        progress("Unpacking\u{2026}", 0.9)
        guard let again = try? Data(contentsOf: dmg, options: .alwaysMapped), sha256Hex(again) == want else {
            return fail("The download changed after it was checked, so it was discarded.")      // closes the check-to-mount gap
        }
        let mount = root.appendingPathComponent("mnt")
        try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path]) == 0 else {
            return fail("Couldn\u{2019}t open the downloaded disk image.")
        }
        defer { run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let app = root.appendingPathComponent("\(appName).app")
        guard run("/usr/bin/ditto", [mount.appendingPathComponent("\(appName).app").path, app.path]) == 0 else {
            return fail("The disk image didn\u{2019}t contain the app.")
        }
        let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard plist?["CFBundleIdentifier"] as? String == bundleID else { return fail("The download isn\u{2019}t \(appName).") }
        guard plist?["CFBundleShortVersionString"] as? String == info.version else {
            return fail("The download held a different version than the release says.")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else {
            return fail("The app\u{2019}s signature didn\u{2019}t check out.")
        }
        try? fm.removeItem(at: dmg)
        progress("Ready", 0.96)
        return Prepared(app: app, hash: executableHash(app))
    }

    /// Fingerprint of the app's executable, taken when the update is verified and re-checked just before it is installed.
    nonisolated static func executableHash(_ app: URL) -> String? {
        (try? Data(contentsOf: app.appendingPathComponent("Contents/MacOS/\(appName)"), options: .mappedIfSafe)).map(sha256Hex)
    }

    /// Hands the verified app to a helper that waits for this app to quit, swaps it in (keeping the old one as a backup)
    /// and relaunches. Returns an error message, or nil once the hand-off has started: the caller should then quit.
    nonisolated static func apply(_ app: URL, expectedHash: String?, dest: URL = Bundle.main.bundleURL) -> String? {
        let fm = FileManager.default
        guard app.path.hasPrefix(cachesDir.path + "/"), dest.pathExtension == "app",
              run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else {
            return "The update didn\u{2019}t pass its final check, so it wasn\u{2019}t installed."
        }
        guard let expectedHash, executableHash(app) == expectedHash else { return "The update changed after it was verified, so it wasn\u{2019}t installed." }
        guard !dest.path.hasPrefix("/Volumes/"), fm.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            return "\(appName) can\u{2019}t replace itself here. Move it to Applications and try again."
        }
        let backup = cachesDir.appendingPathComponent("previous/\(appName).app")
        try? fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = app.deletingLastPathComponent().appendingPathComponent("swap.sh")
        let body = """
        #!/bin/zsh
        PID="$1"; NEW="$2"; DEST="$3"; BACKUP="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        rm -rf "$BACKUP"
        [ -d "$DEST" ] && mv "$DEST" "$BACKUP"
        if ! cp -R "$NEW" "$DEST" || ! /usr/bin/codesign --verify --deep --strict "$DEST"; then rm -rf "$DEST"; [ -d "$BACKUP" ] && mv "$BACKUP" "$DEST"; fi
        open "$DEST"
        """
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil else { return "Couldn\u{2019}t prepare the installer." }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), app.path, dest.path, backup.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "Couldn\u{2019}t start the installer." }
        return nil
    }
}

@MainActor @Observable
final class UpdateModel {
    private(set) var status = UpdateStatus.idle
    private(set) var lastChecked: Date?

    func check() {
        switch status { case .checking, .installing: return; default: break }
        status = .checking
        Task {
            let r = await Task.detached { Updater.check() }.value
            status = r; lastChecked = Date()
        }
    }

    func install(_ info: UpdateInfo) {
        guard case .available = status else { return }
        status = .installing("Starting\u{2026}", 0)
        Task {
            let (stream, cont) = AsyncStream.makeStream(of: (String, Double).self)
            let work = Task.detached { () -> Updater.Prepared in
                let r = Updater.prepare(info) { cont.yield(($0, $1)) }
                cont.finish()
                return r
            }
            for await (msg, f) in stream { status = .installing(msg, f) }
            let r = await work.value
            guard let app = r.app else { status = .failed(r.error ?? "Update failed."); return }
            status = .installing("Installing\u{2026}", 0.98)
            if let e = Updater.apply(app, expectedHash: r.hash) { status = .failed(e) } else { NSApp.terminate(nil) }
        }
    }

    var available: UpdateInfo? { if case .available(let i) = status { return i } else { return nil } }
}
