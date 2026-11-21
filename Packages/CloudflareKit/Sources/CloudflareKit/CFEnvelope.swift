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
}

public struct CFEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let success: Bool
    public let errors: [CFAPIMessage]
    public let result: T?
    public let resultInfo: CFResultInfo?
}
