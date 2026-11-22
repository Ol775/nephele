import Testing
import Foundation
import CryptoKit
@testable import Nephele

@Suite struct UpdaterTests {
    let repo = Updater.repo
    func url(_ s: String) -> URL { URL(string: s)! }

    @Test func versionsCompareNumerically() {
        #expect(isNewer("0.2.0", than: "0.1.9") && isNewer("1.0.0", than: "0.9.9") && isNewer("0.10.0", than: "0.9.0"))
        #expect(!isNewer("0.1.0", than: "0.1.0") && !isNewer("0.1.0", than: "0.1.1"))
    }

    @Test func onlyPlainVersionsAreAccepted() {
        #expect(Updater.isPlainVersion("1.2.3"))
        #expect(!Updater.isPlainVersion("1.2") && !Updater.isPlainVersion("1.2.3-evil") && !Updater.isPlainVersion("../1.2.3") && !Updater.isPlainVersion("1.2.3\n"))
    }

    @Test func onlyThisRepositorysReleaseAssetsAreTrusted() {
        #expect(Updater.isTrustedAsset(url("https://github.com/\(repo)/releases/download/v1.0.0/a.dmg")))
        for bad in ["https://github.com/other/repo/releases/download/v1.0.0/a.dmg", "http://github.com/\(repo)/releases/download/v1.0.0/a.dmg",
                    "https://github.com/\(repo)/releases/download/../../../evil/repo/a.dmg", "https://github.com/\(repo)/releases/download/v1/a.dmg?x=1",
                    "https://github.com:444/\(repo)/releases/download/v1/a.dmg", "https://user@github.com/\(repo)/releases/download/v1/a.dmg",
                    "https://github.com/\(repo)/releases/download//a.dmg", "https://evil.com/\(repo)/releases/download/v1/a.dmg",
                    "https://github.com/\(repo)-evil/releases/download/v1/a.dmg"] {
            #expect(!Updater.isTrustedAsset(url(bad)), "\(bad)")
        }
    }

    @Test func redirectsStayOnGitHub() {
        #expect(Updater.isAllowedRedirectHost("objects.githubusercontent.com") && Updater.isAllowedRedirectHost("github.com"))
        #expect(!Updater.isAllowedRedirectHost("evil.com") && !Updater.isAllowedRedirectHost("githubusercontent.com.evil.com") && !Updater.isAllowedRedirectHost(nil))
    }

    @Test func signaturesAreBoundToVersionAndBytesAndKey() throws {
        let key = Curve25519.Signing.PrivateKey(), pub = key.publicKey.rawRepresentation.base64EncodedString()
        let dmg = Data("image".utf8)
        let sig = try key.signature(for: Updater.signedMessage(version: "1.0.0", dmg: dmg)).base64EncodedString()
        #expect(Updater.verifySignature(Updater.signedMessage(version: "1.0.0", dmg: dmg), base64Signature: sig, publicKey: pub))
        #expect(!Updater.verifySignature(Updater.signedMessage(version: "1.0.1", dmg: dmg), base64Signature: sig, publicKey: pub))
        #expect(!Updater.verifySignature(Updater.signedMessage(version: "1.0.0", dmg: Data("other".utf8)), base64Signature: sig, publicKey: pub))
        #expect(!Updater.verifySignature(Updater.signedMessage(version: "1.0.0", dmg: dmg), base64Signature: sig))   // the built-in key is a different key
        #expect(!Updater.verifySignature(Updater.signedMessage(version: "1.0.0", dmg: dmg), base64Signature: "not base64", publicKey: pub))
    }

    @Test func theBuiltInKeyIsAValidEd25519PublicKey() throws {
        let raw = try #require(Data(base64Encoded: Updater.publicKey))
        _ = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }
}

/// Talks to the real GitHub release. Off by default: run with NEPHELE_LIVE_UPDATE_TEST=1 to check the whole
/// check, download and verify chain (signature, checksum, bundle id, code signature) against the published release.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NEPHELE_LIVE_UPDATE_TEST"] == "1")) struct LiveUpdaterTests {
    @Test func publishedReleaseDownloadsAndVerifies() async throws {
        let status = await Task.detached { Updater.check(installed: "0.0.1") }.value
        guard case .available(let info) = status else { Issue.record("expected an update, got \(status)"); return }
        #expect(info.dmgURL != nil && info.sigURL != nil && info.sha256 != nil)
        let prepared = await Task.detached { Updater.prepare(info) { _, _ in } }.value
        #expect(prepared.error == nil, "\(prepared.error ?? "")")
        let app = try #require(prepared.app)
        #expect(prepared.hash == Updater.executableHash(app))
        #expect(NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String == info.version)
        try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
    }

    @Test func currentVersionIsUpToDate() async {
        let latest = await Task.detached { Updater.check(installed: "99.0.0") }.value
        #expect(latest == .upToDate)
    }
}
