import Foundation
import Observation
import CloudflareKit

/// A change to live DNS that has to be confirmed before it is sent.
struct PendingAction: Equatable, Identifiable {
    enum Kind { case delete, proxy }
    let kind: Kind
    let record: DNSRecord
    var id: String { "\(kind)-\(record.id)" }
}

@MainActor @Observable
final class DNSStore {
    let zone: Zone
    private(set) var records: LoadState<[DNSRecord]> = .idle
    /// Drives the confirmation dialog. Clearing it (the system dismissing the dialog) does not cancel a confirmation in flight.
    private(set) var pending: PendingAction?
    var formError: String?

    @ObservationIgnored private let session: Session
    @ObservationIgnored private var armed: PendingAction?
    private static let proxiable: Set<String> = ["A", "AAAA", "CNAME"]

    init(zone: Zone, session: Session) {
        self.zone = zone
        self.session = session
    }

    func load() async {
        guard let client = session.client else { return }
        if records.value == nil { records = .loading }
        do {
            records = .loaded(try await client.dnsRecords(zoneID: zone.id))
        } catch let error as CloudflareError {
            session.handle(error)
            if records.value == nil { records = .failed(error) }
        } catch {
            if records.value == nil { records = .failed(.transport("unknown")) }
        }
    }

    func add(_ draft: DNSRecordDraft) async {
        formError = nil
        let valid: DNSRecordDraft
        do { valid = try draft.validated(zone: zone.name) }
        catch { formError = (error as? LocalizedError)?.errorDescription; return }
        guard let client = session.client else { return }
        do {
            let created = try await client.createDNSRecord(zoneID: zone.id, valid)
            records = .loaded((records.value ?? []) + [created])
        } catch let error as CloudflareError {
            session.handle(error)
            formError = error.errorDescription
        } catch { formError = "Couldn't add that record." }
    }

    func update(_ record: DNSRecord, with draft: DNSRecordDraft) async {
        formError = nil
        let valid: DNSRecordDraft
        do { valid = try draft.validated(zone: zone.name) }
        catch { formError = (error as? LocalizedError)?.errorDescription; return }
        guard let client = session.client else { return }
        do {
            let updated = try await client.updateDNSRecord(zoneID: zone.id, id: record.id, valid)
            records = .loaded((records.value ?? []).map { $0.id == updated.id ? updated : $0 })
        } catch let error as CloudflareError {
            session.handle(error)
            formError = error.errorDescription
        } catch { formError = "Couldn't save that record." }
    }

    // MARK: Confirmed changes

    func requestDelete(_ record: DNSRecord) { arm(PendingAction(kind: .delete, record: record)) }

    func requestProxyToggle(_ record: DNSRecord) {
        formError = nil
        guard Self.proxiable.contains(record.type.uppercased()) else {
            formError = "\(record.type) records can't be proxied."
            return
        }
        arm(PendingAction(kind: .proxy, record: record))
    }

    /// The user pressed Cancel: forget the request.
    func cancel() { pending = nil; armed = nil }

    /// The system dismissed the dialog (for example after a button press): hide it but keep a confirmation valid.
    func dialogDismissed() { pending = nil }

    /// Only sends a change the user asked for and confirmed, exactly once.
    func confirm(_ action: PendingAction) async {
        guard armed == action, let client = session.client else { return }
        armed = nil
        pending = nil
        do {
            switch action.kind {
            case .delete:
                try await client.deleteDNSRecord(zoneID: zone.id, id: action.record.id)
                records = .loaded((records.value ?? []).filter { $0.id != action.record.id })
            case .proxy:
                let r = action.record
                let draft = DNSRecordDraft(type: r.type, name: r.name, content: r.content, proxied: !(r.proxied ?? false), ttl: r.ttl, priority: r.priority)
                let updated = try await client.updateDNSRecord(zoneID: zone.id, id: r.id, draft)
                records = .loaded((records.value ?? []).map { $0.id == updated.id ? updated : $0 })
            }
        } catch let error as CloudflareError {
            session.handle(error)
            formError = error.errorDescription
        } catch { formError = "Couldn't change that record." }
    }

    private func arm(_ action: PendingAction) {
        pending = action
        armed = action
    }
}
