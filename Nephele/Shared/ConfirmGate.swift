import Observation

/// Holds a change the user must confirm. `pending` drives the dialog; `armed` is what a confirmation may send.
/// The system dismissing the dialog after a button press hides it but keeps the confirmation valid, and a
/// confirmation can be taken once.
@MainActor @Observable
final class ConfirmGate<Item: Equatable & Sendable> {
    private(set) var pending: Item?
    @ObservationIgnored private var armed: Item?

    func request(_ item: Item) { pending = item; armed = item }
    func cancel() { pending = nil; armed = nil }
    func dialogDismissed() { pending = nil }

    /// True only when `item` is the armed request, exactly once.
    func take(_ item: Item) -> Bool {
        guard armed == item else { return false }
        armed = nil
        pending = nil
        return true
    }
}
