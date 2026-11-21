import Foundation
import Observation
import CloudflareKit

@MainActor @Observable
final class DNSStore {
    let zone: Zone
    private(set) var records: LoadState<[DNSRecord]> = .idle
    private(set) var pendingDelete: DNSRecord?
    var formError: String?

    @ObservationIgnored private let session: Session
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

    func toggleProxy(_ record: DNSRecord) async {
        formError = nil
        guard Self.proxiable.contains(record.type.uppercased()) else {
            formError = "\(record.type) records can't be proxied."
            return
        }
        guard let client = session.client else { return }
        let draft = DNSRecordDraft(type: record.type, name: record.name, content: record.content, proxied: !(record.proxied ?? false), ttl: record.ttl, priority: record.priority)
        do {
            let updated = try await client.updateDNSRecord(zoneID: zone.id, id: record.id, draft)
            records = .loaded((records.value ?? []).map { $0.id == updated.id ? updated : $0 })
        } catch let error as CloudflareError {
            session.handle(error)
            formError = error.errorDescription
        } catch { formError = "Couldn't update that record." }
    }

    func requestDelete(_ record: DNSRecord) { pendingDelete = record }
    func cancelDelete() { pendingDelete = nil }

    /// Only acts on a record the user has asked to delete and then confirmed.
    func confirmDelete() async {
        guard let record = pendingDelete, let client = session.client else { return }
        pendingDelete = nil
        do {
            try await client.deleteDNSRecord(zoneID: zone.id, id: record.id)
            records = .loaded((records.value ?? []).filter { $0.id != record.id })
        } catch let error as CloudflareError {
            session.handle(error)
            formError = error.errorDescription
        } catch { formError = "Couldn't delete that record." }
    }
}
