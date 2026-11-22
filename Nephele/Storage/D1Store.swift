import Foundation
import Observation
import CloudflareKit

/// A statement that changes data or schema, confirmed before it runs.
struct D1Write: Equatable, Sendable {
    let sql: String
    func title(database: String) -> String { "Run this on \(database)?" }
    func message(database: String) -> String { "This statement can change or delete data in \(database). It runs straight away and can't be undone." }
}

@MainActor @Observable
final class D1Store {
    private(set) var databases: LoadState<[D1Database]> = .idle
    private(set) var selected: D1Database?
    private(set) var tables: [String] = []
    private(set) var results: LoadState<[D1Result]> = .idle
    var sql = ""
    private(set) var canWrite = true
    var formError: String?
    let confirm = ConfirmGate<D1Write>()

    @ObservationIgnored let session: Session

    init(session: Session) { self.session = session }

    func reset() {
        databases = .idle; selected = nil; tables = []; results = .idle; sql = ""; canWrite = true; formError = nil; confirm.cancel()
    }

    private var account: String? { session.selectedAccountID }

    func load() async {
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        if databases.value == nil { databases = .loading }
        do {
            let list = try await client.d1Databases(accountID: account).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            guard epoch == session.identityEpoch else { return }
            databases = .loaded(list)
        } catch let error as CloudflareError {
            guard epoch == session.identityEpoch else { return }
            session.handle(error)
            if databases.value == nil { databases = .failed(error) }
        } catch { if databases.value == nil { databases = .failed(.transport("unknown")) } }
    }

    func select(_ db: D1Database?) async {
        selected = db; tables = []; results = .idle; sql = ""; formError = nil
        await loadTables()
    }

    private func loadTables() async {
        guard let db = selected, let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        if let r = try? await client.queryD1(accountID: account, database: db.id, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY name").first,
           selected == db, epoch == session.identityEpoch {
            tables = r.rows.compactMap(\.first)
        }
    }

    /// Reads run straight away; anything that could change data waits for confirmation.
    func run() async {
        formError = nil
        let text = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, selected != nil else { return }
        if D1SQL.isReadOnly(text) { await execute(text) } else { confirm.request(D1Write(sql: text)) }
    }

    func confirmWrite(_ write: D1Write) async {
        guard confirm.take(write) else { return }
        await execute(write.sql)
    }

    private func execute(_ text: String) async {
        guard let client = session.client, let account, let db = selected else { return }
        let epoch = session.identityEpoch
        results = .loading
        do {
            let out = try await client.queryD1(accountID: account, database: db.id, sql: text)
            // Another database or account may have been picked while this ran.
            guard selected == db, epoch == session.identityEpoch else { return }
            results = .loaded(out)
            if !D1SQL.isReadOnly(text) { await loadTables() }
        } catch let error as CloudflareError {
            guard selected == db, epoch == session.identityEpoch else { return }
            if case .permissionDenied = error, !D1SQL.isReadOnly(text) { session.handle(error); canWrite = false; formError = StorageCopy.editHint("D1 Edit"); results = .idle }
            else { session.handle(error); results = .failed(error) }
        } catch { results = .failed(.transport("unknown")) }
    }

    func create(_ name: String) async {
        formError = nil
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        do {
            let db = try await client.createD1Database(accountID: account, name: name.trimmingCharacters(in: .whitespaces))
            guard epoch == session.identityEpoch else { return }
            databases = .loaded(((databases.value ?? []) + [db]).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        } catch { report(error, "Couldn't create that database.") }
    }

    func delete(_ db: D1Database, typedName: String) async {
        formError = nil
        guard typedName == db.name else { formError = "Type \(db.name) exactly to delete it."; return }
        guard let client = session.client, let account else { return }
        let epoch = session.identityEpoch
        do {
            try await client.deleteD1Database(accountID: account, database: db.id)
            guard epoch == session.identityEpoch else { return }
            databases = .loaded((databases.value ?? []).filter { $0.id != db.id })
            if selected == db { selected = nil; tables = []; results = .idle }
        } catch { report(error, "Couldn't delete that database.") }
    }

    private func report(_ error: any Error, _ fallback: String) {
        if let e = error as? CloudflareError {
            if case .permissionDenied = e { session.handle(e); canWrite = false; formError = StorageCopy.editHint("D1 Edit") } else { session.handle(e); formError = e.errorDescription }
        } else { formError = (error as? LocalizedError)?.errorDescription ?? fallback }
    }
}
