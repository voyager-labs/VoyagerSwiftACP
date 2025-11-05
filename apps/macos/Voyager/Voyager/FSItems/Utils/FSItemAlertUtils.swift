import AppKit

enum FSItemAlertUtils {
    @MainActor
    static func showDeleteConfirmationAlert(itemNames: [String]) -> Bool {
        let alert = NSAlert()

        if itemNames.count == 1 {
            alert.messageText = "Are you sure you want to delete \"\(itemNames[0])\"?"
        } else {
            alert.messageText = "Are you sure you want to delete \(itemNames.count) items?"
        }
        alert.informativeText = "This item will be deleted immediately. You can't undo this action."

        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        alert.alertStyle = .critical
        alert.buttons[0].hasDestructiveAction = true

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }
}
