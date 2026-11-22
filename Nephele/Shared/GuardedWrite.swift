import Foundation
import CloudflareKit

enum WriteOutcome: Equatable { case done, stale, denied(String), failed(String) }

/// Runs one Cloudflare write for a store. `isCurrent` turns false if the identity changed meanwhile, so late results aren't applied.
/// A 403 counts as "token lacks `permission`" only when Cloudflare says nothing else (plan limits and the like name themselves).
@MainActor
func guardedWrite(_ session: Session, permission: String, _ body: (CFClient, @MainActor @Sendable () -> Bool) async throws -> Void) async -> WriteOutcome {
    guard let client = session.client else { return .stale }
    let epoch = session.identityEpoch
    do { try await body(client, { [session] in epoch == session.identityEpoch }); return epoch == session.identityEpoch ? .done : .stale }
    catch let error as CloudflareError {
        guard epoch == session.identityEpoch else { return .stale }
        session.handle(error)
        if case .permissionDenied(let why) = error {
            let m = why?.lowercased()
            if m == nil || m!.contains("auth") || m!.contains("permission") { return .denied(StorageCopy.editHint(permission)) }
            return .failed(why ?? "Cloudflare refused that change.")
        }
        return .failed(error.errorDescription ?? "Couldn't save that change.")
    } catch { return .failed("Couldn't save that change.") }
}

/// Loads one list for a store, ignoring results that arrive after an account switch.
@MainActor
func loadList<S: AnyObject, T: Sendable>(_ session: Session, _ store: S, _ key: ReferenceWritableKeyPath<S, LoadState<T>>, _ fetch: (CFClient) async throws -> T) async {
    guard let client = session.client else { return }
    let epoch = session.identityEpoch
    if store[keyPath: key].value == nil { store[keyPath: key] = .loading }
    do {
        let v = try await fetch(client)
        guard epoch == session.identityEpoch else { return }
        store[keyPath: key] = .loaded(v)
    } catch let error as CloudflareError {
        guard epoch == session.identityEpoch else { return }
        session.handle(error)
        if store[keyPath: key].value == nil { store[keyPath: key] = .failed(error) }
    } catch { if store[keyPath: key].value == nil { store[keyPath: key] = .failed(.transport("unknown")) } }
}

/// Async stand-in for `Result { try await … }`, which older toolchains (CI) don't have.
func capture<T: Sendable>(_ body: @Sendable () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await body()) } catch { return .failure(error) }
}
