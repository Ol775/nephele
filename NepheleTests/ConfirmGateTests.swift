import Testing
@testable import Nephele

@MainActor
@Suite struct ConfirmGateTests {
    @Test func takeSucceedsOnlyForArmedItemAndOnlyOnce() {
        let gate = ConfirmGate<String>()
        gate.request("delete a")
        #expect(gate.take("delete b") == false)
        #expect(gate.take("delete a") == true)
        #expect(gate.take("delete a") == false)
        #expect(gate.pending == nil)
    }

    @Test func dialogDismissedKeepsArmed() {
        let gate = ConfirmGate<String>()
        gate.request("x")
        gate.dialogDismissed()
        #expect(gate.pending == nil)
        #expect(gate.take("x") == true)
    }

    @Test func cancelClearsArmed() {
        let gate = ConfirmGate<String>()
        gate.request("x")
        gate.cancel()
        #expect(gate.pending == nil)
        #expect(gate.take("x") == false)
    }
}
