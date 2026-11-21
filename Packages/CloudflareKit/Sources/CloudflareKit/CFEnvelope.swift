import Foundation

public struct CFAPIMessage: Decodable, Sendable, Equatable {
    public let code: Int
    public let message: String
}

public struct CFResultInfo: Decodable, Sendable, Equatable {
    public let page: Int
    public let perPage: Int
    public let totalPages: Int
    public let totalCount: Int
    /// Cursor-paginated lists (KV keys, R2 objects) carry this instead of page counts. Empty means the last page.
    public let cursor: String?

    private enum CodingKeys: String, CodingKey { case page, perPage, totalPages, totalCount, cursor }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        perPage = try c.decodeIfPresent(Int.self, forKey: .perPage) ?? 0
        totalPages = try c.decodeIfPresent(Int.self, forKey: .totalPages) ?? 1
        totalCount = try c.decodeIfPresent(Int.self, forKey: .totalCount) ?? 0
        let raw = try c.decodeIfPresent(String.self, forKey: .cursor)
        cursor = (raw?.isEmpty ?? true) ? nil : raw
    }
}

public struct CFEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let success: Bool
    public let errors: [CFAPIMessage]
    public let result: T?
    public let resultInfo: CFResultInfo?
}
