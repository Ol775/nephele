import Foundation
import Observation

@MainActor @Observable
final class R2Store {
    @ObservationIgnored private let session: Session
    init(session: Session) { self.session = session }
    func reset() {}
}
