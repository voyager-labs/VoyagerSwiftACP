import AppKit

enum FileManagerAlertUtils {
    @MainActor
    static func showUnsavedNavigationAlert() -> FileManagerFeature.UnsavedNavigationChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unsaved Filters"
        alert.informativeText = "You have unsaved filter changes. What would you like to do?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }
}
