import CloudflareKit

enum LoadState<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(CloudflareError)

    var value: T? { if case .loaded(let v) = self { v } else { nil } }
    var failure: CloudflareError? { if case .failed(let e) = self { e } else { nil } }
    var isLoading: Bool { if case .loading = self { true } else { false } }
}
