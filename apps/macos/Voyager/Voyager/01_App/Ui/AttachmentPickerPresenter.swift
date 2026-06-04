import AppKit
import Foundation

enum AttachmentPickerPresenter {
    @MainActor
    static func pickAttachments() -> [URL] {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Add Attachments"
        panel.message = "Choose files, folders, or collections to add to the current chat context."
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
