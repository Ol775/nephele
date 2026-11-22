import Foundation

// MARK: Email Routing (zone rules, account destination addresses)

public struct EmailMatcher: Codable, Sendable, Equatable, Hashable {
    public let type: String; public let field: String?; public let value: String?
    public init(type: String, field: String?, value: String?) { self.type = type; self.field = field; self.value = value }
}
public struct EmailAction: Codable, Sendable, Equatable, Hashable {
    public let type: String; public let value: [String]?
    public init(type: String, value: [String]?) { self.type = type; self.value = value }
}

public struct EmailRule: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let enabled: Bool?
    public let priority: Int?
    public let matchers: [EmailMatcher]?
    public let actions: [EmailAction]?
    public init(id: String, name: String? = nil, enabled: Bool? = nil, priority: Int? = nil, matchers: [EmailMatcher]? = nil, actions: [EmailAction]? = nil) {
        self.id = id; self.name = name; self.enabled = enabled; self.priority = priority; self.matchers = matchers; self.actions = actions
    }
    /// The address the rule listens on, or nil for catch-all and other matchers.
    public var from: String? { matchers?.first { $0.type == "literal" }?.value }
    public var destinations: [String] { actions?.flatMap { $0.value ?? [] } ?? [] }
    public var isForward: Bool { actions?.contains { $0.type == "forward" } == true }
}

public struct EmailRoutingStatus: Codable, Sendable, Equatable { public let enabled: Bool?; public let status: String? }

public struct EmailAddress: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let email: String
    /// A timestamp once the owner has clicked the verification link.
    public let verified: String?
    public init(id: String, email: String, verified: String? = nil) { self.id = id; self.email = email; self.verified = verified }
}

/// Loose on purpose: Cloudflare does the real validation, this only stops obvious typos before a live mail rule is written.
public func validEmail(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces)
    let parts = t.split(separator: "@", omittingEmptySubsequences: false)
    return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !t.contains(" ")
}

private struct EmailRuleBody: Encodable, Sendable {
    let name: String; let enabled: Bool; let priority: Int?
    let matchers: [EmailMatcher]; let actions: [EmailAction]
}

// MARK: WAF custom rules (ruleset phase http_request_firewall_custom)

public struct FirewallRule: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let action: String
    public let expression: String
    public let description: String?
    public let enabled: Bool?
    public let actionParameters: JSONValue?
    public let logging: JSONValue?
    public init(id: String, action: String, expression: String, description: String? = nil, enabled: Bool? = nil, actionParameters: JSONValue? = nil, logging: JSONValue? = nil) {
        self.id = id; self.action = action; self.expression = expression; self.description = description; self.enabled = enabled
        self.actionParameters = actionParameters; self.logging = logging
    }
    /// True when this model holds the whole rule. Toggling anything else would drop fields (custom block pages, skip targets, logging) on the PATCH.
    public var isPlain: Bool { actionParameters == nil && logging == nil && FirewallRuleDraft.actions.contains(action) }
}

public struct FirewallRuleset: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let rules: [FirewallRule]?
    public init(id: String, rules: [FirewallRule]? = nil) { self.id = id; self.rules = rules }
}

public struct FirewallRuleDraft: Codable, Sendable, Equatable {
    public var action: String, expression: String, description: String, enabled: Bool
    public init(action: String, expression: String, description: String, enabled: Bool = true) {
        self.action = action; self.expression = expression; self.description = description; self.enabled = enabled
    }
    public static let actions = ["block", "managed_challenge", "js_challenge", "challenge", "log"]
    public var isValid: Bool {
        Self.actions.contains(action) && !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct RulesetRules: Encodable, Sendable { let rules: [FirewallRuleDraft] }

// MARK: Turnstile

public struct TurnstileWidget: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let sitekey: String
    public let name: String
    public let mode: String?
    public let domains: [String]?
    public let createdOn: String?
    public var id: String { sitekey }
    public init(sitekey: String, name: String, mode: String? = nil, domains: [String]? = nil, createdOn: String? = nil) {
        self.sitekey = sitekey; self.name = name; self.mode = mode; self.domains = domains; self.createdOn = createdOn
    }
}

/// The secret is returned once, on creation, and is deliberately not part of `TurnstileWidget`.
public struct CreatedTurnstile: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let widget: TurnstileWidget
    public let secret: String
    public var description: String { "CreatedTurnstile(\(widget.name), secret hidden)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["widget": widget]) }
}

public let turnstileModes = ["managed", "non-interactive", "invisible"]

private struct TurnstileBody: Encodable, Sendable { let name: String; let domains: [String]; let mode: String }
private struct TurnstileSecretWire: Decodable, Sendable { let secret: String? }

/// Hostnames only: no scheme, path or spaces.
public func parseTurnstileDomains(_ text: String) -> [String] {
    text.split(whereSeparator: { ",\n ".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
}
public func validHostname(_ s: String) -> Bool {
    !s.isEmpty && s.contains(".") && !s.contains("/") && !s.contains(":") && !s.contains(" ")
}

// MARK: Gateway

public struct GatewayRule: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let action: String?
    public let enabled: Bool?
    public let description: String?
    public let filters: [String]?
    public let precedence: Int?
    public init(id: String, name: String, action: String? = nil, enabled: Bool? = nil, description: String? = nil, filters: [String]? = nil, precedence: Int? = nil) {
        self.id = id; self.name = name; self.action = action; self.enabled = enabled; self.description = description; self.filters = filters; self.precedence = precedence
    }
}

// MARK: Client

extension CFClient {
    public func emailRoutingStatus(zoneID: String) async throws -> EmailRoutingStatus {
        try await send("GET", "/zones/\(pathSegment(zoneID))/email/routing")
    }

    public func emailRules(zoneID: String) async throws -> [EmailRule] {
        try await getAll("/zones/\(pathSegment(zoneID))/email/routing/rules", perPage: 50)
    }

    public func emailAddresses(accountID: String) async throws -> [EmailAddress] {
        try await getAll("/accounts/\(pathSegment(accountID))/email/routing/addresses", perPage: 50)
    }

    /// A forwarding rule: mail to `address` goes to `destination`, which must already be a verified destination.
    public func createEmailRule(zoneID: String, address: String, destination: String) async throws -> EmailRule {
        let address = address.trimmingCharacters(in: .whitespaces).lowercased()
        guard validEmail(address), validEmail(destination) else { throw CloudflareError.api(code: 0, message: "Enter a full email address.") }
        let body = EmailRuleBody(name: "Forward \(address)", enabled: true, priority: nil,
                                 matchers: [EmailMatcher(type: "literal", field: "to", value: address)],
                                 actions: [EmailAction(type: "forward", value: [destination])])
        return try await send("POST", "/zones/\(pathSegment(zoneID))/email/routing/rules", body: body)
    }

    /// PUT replaces the whole rule, so the rest of it is sent back unchanged.
    public func setEmailRule(zoneID: String, rule: EmailRule, enabled: Bool) async throws -> EmailRule {
        let body = EmailRuleBody(name: rule.name ?? "", enabled: enabled, priority: rule.priority, matchers: rule.matchers ?? [], actions: rule.actions ?? [])
        return try await send("PUT", "/zones/\(pathSegment(zoneID))/email/routing/rules/\(pathSegment(rule.id))", body: body)
    }

    public func deleteEmailRule(zoneID: String, id: String) async throws {
        _ = try await raw("DELETE", "/zones/\(pathSegment(zoneID))/email/routing/rules/\(pathSegment(id))")
    }

    /// nil when the zone has no custom rules yet (Cloudflare answers "not found" until the first one is added).
    public func firewallRuleset(zoneID: String) async throws -> FirewallRuleset? {
        do { return try await send("GET", "/zones/\(pathSegment(zoneID))/rulesets/phases/http_request_firewall_custom/entrypoint") }
        catch CloudflareError.api(let code, let message) where code == 10003 { return nil }
        catch CloudflareError.transport(let why) where why == "HTTP 404" { return nil }
    }

    /// Adds a rule; creates the zone's custom ruleset first when there isn't one.
    public func createFirewallRule(zoneID: String, rulesetID: String?, _ draft: FirewallRuleDraft) async throws -> FirewallRuleset {
        guard draft.isValid else { throw CloudflareError.api(code: 0, message: "A rule needs an action and an expression.") }
        let zone = pathSegment(zoneID)
        if let rulesetID {
            return try await send("POST", "/zones/\(zone)/rulesets/\(pathSegment(rulesetID))/rules", body: draft)
        }
        return try await send("PUT", "/zones/\(zone)/rulesets/phases/http_request_firewall_custom/entrypoint", body: RulesetRules(rules: [draft]))
    }

    public func setFirewallRule(zoneID: String, rulesetID: String, rule: FirewallRule, enabled: Bool) async throws -> FirewallRuleset {
        guard rule.isPlain else { throw CloudflareError.api(code: 0, message: "This rule has options Nephele can't show. Change it in the Cloudflare dashboard.") }
        let draft = FirewallRuleDraft(action: rule.action, expression: rule.expression, description: rule.description ?? "", enabled: enabled)
        return try await send("PATCH", "/zones/\(pathSegment(zoneID))/rulesets/\(pathSegment(rulesetID))/rules/\(pathSegment(rule.id))", body: draft)
    }

    public func deleteFirewallRule(zoneID: String, rulesetID: String, id: String) async throws {
        _ = try await raw("DELETE", "/zones/\(pathSegment(zoneID))/rulesets/\(pathSegment(rulesetID))/rules/\(pathSegment(id))")
    }

    public func turnstileWidgets(accountID: String) async throws -> [TurnstileWidget] {
        try await getAll("/accounts/\(pathSegment(accountID))/challenges/widgets", perPage: 100)
    }

    public func createTurnstile(accountID: String, name: String, domains: [String], mode: String) async throws -> CreatedTurnstile {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validTunnelName(name) else { throw WorkerValidationError.invalidName }
        guard !domains.isEmpty, domains.allSatisfy(validHostname), turnstileModes.contains(mode) else { throw CloudflareError.api(code: 0, message: "Enter at least one hostname, such as example.com.") }
        let body = try JSONEncoder().encode(TurnstileBody(name: name, domains: domains, mode: mode))
        let data = try await raw("POST", "/accounts/\(pathSegment(accountID))/challenges/widgets", body: body)
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        guard let widget = try? d.decode(CFEnvelope<TurnstileWidget>.self, from: data).result,
              let secret = try? d.decode(CFEnvelope<TurnstileSecretWire>.self, from: data).result?.secret else { throw CloudflareError.api(code: 0, message: "The widget may have been created, but its secret couldn't be read. Check Turnstile in the Cloudflare dashboard, where you can rotate the secret.") }
        return CreatedTurnstile(widget: widget, secret: secret)
    }

    public func deleteTurnstile(accountID: String, sitekey: String) async throws {
        _ = try await raw("DELETE", "/accounts/\(pathSegment(accountID))/challenges/widgets/\(pathSegment(sitekey))")
    }

    public func gatewayRules(accountID: String) async throws -> [GatewayRule] {
        try await send("GET", "/accounts/\(pathSegment(accountID))/gateway/rules")
    }

    public func deleteGatewayRule(accountID: String, id: String) async throws {
        _ = try await raw("DELETE", "/accounts/\(pathSegment(accountID))/gateway/rules/\(pathSegment(id))")
    }
}
