import Foundation
import Observation

@MainActor @Observable
final class D1Store {
    @ObservationIgnored private let session: Session
    init(session: Session) { self.session = session }
    func reset() {}
}
