import Foundation

public struct WorkerModule: Sendable, Equatable {
    public var name: String
    public var contentType: String
    public var data: Data
    public init(name: String, contentType: String, data: Data) { self.name = name; self.contentType = contentType; self.data = data }
    /// The module as text, or nil when it isn't valid UTF-8 (a WebAssembly module, say).
    public var text: String? { String(data: data, encoding: .utf8) }
}

public struct WorkerCode: Sendable, Equatable {
    public var mainModule: String
    public var modules: [WorkerModule]
    public init(mainModule: String, modules: [WorkerModule]) { self.mainModule = mainModule; self.modules = modules }
}

private struct RawResult<T: Decodable>: Decodable { let result: T }

extension CFClient {
    private static let moduleType = "application/javascript+module"

    /// The Worker's current modules. Old service-worker scripts come back as one plain body.
    public func workerCode(accountID: String, script: String) async throws -> WorkerCode {
        let (data, headers) = try await download("/accounts/\(accountID)/workers/scripts/\(script)/content/v2")
        let type = headers["content-type"] ?? ""
        guard type.lowercased().hasPrefix("multipart/") else {
            return WorkerCode(mainModule: "worker.js", modules: [WorkerModule(name: "worker.js", contentType: "application/javascript", data: data)])
        }
        let modules = MultipartForm.parse(data, contentType: type).compactMap { part -> WorkerModule? in
            guard let name = part.filename ?? part.name else { return nil }
            return WorkerModule(name: name, contentType: part.contentType ?? Self.moduleType, data: part.data)
        }
        guard !modules.isEmpty else { throw CloudflareError.decoding("script content") }
        return WorkerCode(mainModule: headers["cf-entrypoint"] ?? modules[0].name, modules: modules)
    }

    /// Saves the code as a new version. It is not live until it is deployed. Existing bindings are kept by type.
    public func uploadVersion(accountID: String, script: String, code: WorkerCode, settings: WorkerSettings, message: String) async throws -> WorkerVersion {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw WorkerValidationError.messageRequired }
        guard message.utf8.count <= 1000 else { throw WorkerValidationError.messageTooLong }
        var meta: [String: JSONValue] = [
            "main_module": .string(code.mainModule),
            "compatibility_flags": .array(settings.compatibilityFlags.map { .string($0) }),
            "keep_bindings": .array(Set(settings.bindings.map(\.type)).sorted().map { .string($0) }),
            "annotations": .object(["workers/message": .string(message)]),
        ]
        if let date = settings.compatibilityDate { meta["compatibility_date"] = .string(date) }
        var form = MultipartForm()
        form.addJSON(name: "metadata", try JSONEncoder().encode(JSONValue.object(meta)))
        for module in code.modules { form.addFile(name: module.name, filename: module.name, contentType: module.contentType, data: module.data) }
        let data = try await raw("POST", "/accounts/\(accountID)/workers/scripts/\(script)/versions", body: form.body, contentType: form.contentType)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        do { return try decoder.decode(RawResult<WorkerVersion>.self, from: data).result }
        catch { throw CloudflareError.decoding("version") }
    }
}
