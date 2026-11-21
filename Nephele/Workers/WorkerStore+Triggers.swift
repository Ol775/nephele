import Foundation
import CloudflareKit

struct ZoneRoute: Equatable, Sendable, Identifiable {
    let route: WorkerRoute
    let zone: Zone
    var id: String { route.id }
}

struct WorkerTriggers: Equatable, Sendable {
    var routes: [ZoneRoute]
    var domains: [WorkerDomain]
    var crons: [String]
    /// Zones whose routes this token couldn't read, shown so a short list isn't mistaken for a complete one.
    var unreadableZones: [String]
}

extension WorkerStore {
    static let routesHint = "This token can't change routes for that domain. Add Workers Routes Edit for it, then try again."
    static let domainsHint = "This token can't change custom domains. Add Workers Routes Edit and edit access for that domain, then try again."

    /// Loads this Worker's routes (across the given zones, four at a time), custom domains and cron triggers.
    func loadTriggers(zones: [Zone]) async {
        guard let client = session.client, let account = activeAccount else { return }
        let name = script.id
        let zones = zones.filter { $0.accountID == account }
        if triggers.value == nil { triggers = .loading }
        do {
            async let domains = client.workerDomains(accountID: account, service: name)
            async let crons = client.workerSchedules(accountID: account, script: name)
            var routes: [ZoneRoute] = []
            var unreadable: [String] = []
            var index = 0
            while index < zones.count {
                let batch = Array(zones[index..<min(index + 4, zones.count)])
                index += 4
                await withTaskGroup(of: (Zone, Result<[WorkerRoute], any Error>).self) { group in
                    for zone in batch { group.addTask { (zone, await Result { try await client.workerRoutes(zoneID: zone.id) }) } }
                    for await (zone, result) in group {
                        switch result {
                        case .success(let list): routes += list.filter { $0.script == name }.map { ZoneRoute(route: $0, zone: zone) }
                        case .failure: unreadable.append(zone.name)
                        }
                    }
                }
            }
            triggers = .loaded(WorkerTriggers(routes: routes.sorted { $0.route.pattern < $1.route.pattern },
                                              domains: try await domains, crons: try await crons, unreadableZones: unreadable.sorted()))
        } catch let error as CloudflareError {
            session.handle(error)
            triggers = .failed(error)
        } catch { triggers = .failed(.transport("unknown")) }
    }

    func addCron(_ cron: String) async {
        formError = nil
        let cron = cron.trimmingCharacters(in: .whitespaces)
        guard validCron(cron) else { formError = "A cron trigger needs five fields, such as */30 * * * *."; return }
        guard var t = triggers.value else { return }
        guard !t.crons.contains(cron) else { formError = "That schedule is already set."; return }
        let updated = t.crons + [cron]
        await write { client, account, name in
            try await client.setWorkerSchedules(accountID: account, script: name, updated)
            t.crons = updated
            self.triggers = .loaded(t)
        }
    }

    func addRoute(pattern: String, zone: Zone) async {
        formError = nil
        let pattern = pattern.trimmingCharacters(in: .whitespaces)
        guard validRoutePattern(pattern, zone: zone.name) else { formError = "A route pattern has to match \(zone.name) or a subdomain, such as api.\(zone.name)/*."; return }
        await write(deniedHint: Self.routesHint) { client, _, name in
            try await client.createWorkerRoute(zoneID: zone.id, pattern: pattern, script: name)
            await self.loadTriggers(zones: self.triggers.value.map { t in Array(Set(t.routes.map(\.zone)).union([zone])) } ?? [zone])
        }
    }

    func attachDomain(hostname: String, zone: Zone) async {
        formError = nil
        let host = hostname.trimmingCharacters(in: .whitespaces).lowercased()
        guard host == zone.name || host.hasSuffix("." + zone.name) else { formError = "That hostname has to be \(zone.name) or a subdomain of it."; return }
        await write(deniedHint: Self.domainsHint) { client, account, name in
            try await client.attachWorkerDomain(accountID: account, hostname: host, script: name, zoneID: zone.id)
            if var t = self.triggers.value {
                t.domains = (try? await client.workerDomains(accountID: account, service: name)) ?? t.domains
                self.triggers = .loaded(t)
            }
        }
    }

    func confirmTriggerChange(_ change: WorkerChange) async {
        guard var t = triggers.value else { return }
        switch change {
        case .removeCron(let cron):
            let updated = t.crons.filter { $0 != cron }
            await write { client, account, name in
                try await client.setWorkerSchedules(accountID: account, script: name, updated)
                t.crons = updated
                self.triggers = .loaded(t)
            }
        case .removeRoute(let id, _, let zoneID):
            await write(deniedHint: Self.routesHint) { client, _, _ in
                try await client.deleteWorkerRoute(zoneID: zoneID, id: id)
                t.routes.removeAll { $0.id == id }
                self.triggers = .loaded(t)
            }
        case .detachDomain(let id, _):
            await write(deniedHint: Self.domainsHint) { client, account, _ in
                try await client.detachWorkerDomain(accountID: account, id: id)
                t.domains.removeAll { $0.id == id }
                self.triggers = .loaded(t)
            }
        default: break
        }
    }
}
