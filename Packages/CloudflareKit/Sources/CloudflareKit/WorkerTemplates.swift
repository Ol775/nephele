import Foundation

public enum WorkerTemplate: String, CaseIterable, Sendable, Identifiable {
    case hello, httpAPI, scheduledJob
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hello: "Hello world"
        case .httpAPI: "HTTP API"
        case .scheduledJob: "Scheduled job"
        }
    }

    /// A suggested cron trigger to add after deploying (scheduled job only).
    public var cron: String? { self == .scheduledJob ? "0 6 * * *" : nil }

    public var source: String {
        switch self {
        case .hello:
            """
            export default {
              async fetch(request, env, ctx) {
                return new Response("Hello, world!");
              },
            };

            """
        case .httpAPI:
            """
            export default {
              async fetch(request, env, ctx) {
                const url = new URL(request.url);
                if (url.pathname === "/api/health") {
                  return Response.json({ ok: true, time: new Date().toISOString() });
                }
                return Response.json({ error: "Not found" }, { status: 404 });
              },
            };

            """
        case .scheduledJob:
            """
            export default {
              async scheduled(controller, env, ctx) {
                console.log("Ran at", new Date(controller.scheduledTime).toISOString());
              },
            };

            """
        }
    }
}

extension CFClient {
    /// Creates a Worker and uploads the template as its first version. It is not deployed.
    public func createWorker(accountID: String, name: String, template: WorkerTemplate, now: Date = Date()) async throws -> WorkerVersion {
        guard validWorkerName(name) else { throw WorkerValidationError.invalidName }
        let body = try JSONEncoder().encode(JSONValue.object(["name": .string(name)]))
        _ = try await raw("POST", "/accounts/\(accountID)/workers/workers", body: body)
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        let code = WorkerCode(mainModule: "index.js", modules: [WorkerModule(name: "index.js", contentType: "application/javascript+module", data: Data(template.source.utf8))])
        return try await uploadVersion(accountID: accountID, script: name, code: code,
                                       settings: WorkerSettings(compatibilityDate: day.string(from: now)), message: "Created from template: \(template.title)")
    }

    public func deleteWorker(accountID: String, script: String) async throws {
        _ = try await raw("DELETE", "/accounts/\(accountID)/workers/scripts/\(script)", query: [URLQueryItem(name: "force", value: "true")])
    }
}
