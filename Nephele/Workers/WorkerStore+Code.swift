import Foundation
import CloudflareKit

extension WorkerStore {
    var extraModules: [WorkerModule] {
        guard let code = code.value else { return [] }
        return code.modules.filter { $0.name != code.mainModule }
    }

    /// Why the editor can't be used, or nil when the main module is editable text.
    var readOnlyReason: String? {
        guard let code = code.value else { return nil }
        guard let main = code.modules.first(where: { $0.name == code.mainModule }) else { return "This Worker has no main module Nephele can read." }
        return main.text == nil ? "The main module isn't text, so it can't be edited here." : nil
    }

    var hasUnsavedChanges: Bool { loadedText.map { $0 != draft } ?? false }

    func loadCode() async {
        // Coming back to this tab must never throw away unsaved edits.
        guard !hasUnsavedChanges else { return }
        guard let client = session.client, let account = activeAccount else { return }
        if code.value == nil { code = .loading }
        do {
            let loaded = try await client.workerCode(accountID: account, script: script.id)
            code = .loaded(loaded)
            let text = loaded.modules.first { $0.name == loaded.mainModule }?.text
            loadedText = text
            draft = text ?? ""
        } catch let error as CloudflareError {
            session.handle(error)
            code = .failed(error)
        } catch { code = .failed(.transport("unknown")) }
    }

    /// Saves the draft as a new version. It is not live until it is deployed.
    func saveVersion(message: String) async {
        formError = nil
        guard readOnlyReason == nil, let current = code.value else { return }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { formError = WorkerValidationError.messageRequired.errorDescription; return }
        guard activeAccount != nil else { formError = Self.wrongAccount; return }
        var updated = current
        if let i = updated.modules.firstIndex(where: { $0.name == updated.mainModule }) { updated.modules[i].data = Data(draft.utf8) }
        let text = draft
        await write { client, account, name in
            let currentSettings = try await self.freshSettings(client, account, name)
            let version = try await client.uploadVersion(accountID: account, script: name, code: updated, settings: currentSettings, message: message)
            self.code = .loaded(updated)
            self.loadedText = text
            self.lastSavedVersionID = version.id
            await self.loadVersions()
        }
    }
}
