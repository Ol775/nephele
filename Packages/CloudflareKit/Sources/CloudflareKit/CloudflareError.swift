import Foundation

public enum CloudflareError: Error, Sendable, Equatable {
    case unauthorized
    case permissionDenied(String?)
    case rateLimited(retryAfter: TimeInterval?)
    case api(code: Int, message: String)
    case transport(String)
    case decoding(String)
}

extension CloudflareError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Your API token isn't valid or has been revoked. Add a new one in Settings."
        case .permissionDenied: "Your API token doesn't have permission for this. Add the missing permission, then refresh."
        case .rateLimited: "Cloudflare is limiting requests right now. Try again in a moment."
        case .api(_, let message): message
        case .transport: "Couldn't reach Cloudflare. Check your connection and try again."
        case .decoding: "Cloudflare returned something unexpected."
        }
    }
}
