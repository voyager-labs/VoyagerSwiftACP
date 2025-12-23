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

    @MainActor
    static func showRenameConflictAlert(itemName: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The name \"\(itemName)\" is already taken."
        alert.informativeText = "Please choose a different name."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    static func showReplaceAlert(
        itemName: String,
        context: ReplaceContext,
    ) -> ReplaceAlertResponse {
        let alert = NSAlert()
        alert.alertStyle = .warning

        switch context {
        case .putBack:
            alert.messageText = "A newer item named \"\(itemName)\" already exists in this location. Do you want to replace it with the older one you're moving?"
        case .move:
            alert.messageText = "An older item named \"\(itemName)\" already exists in this location. Do you want to replace it with the newer one you're moving?"
        }

        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Replace")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .stop : .replace
    }

    enum ReplaceContext {
        case putBack
        case move
    }

    enum ReplaceAlertResponse {
        case stop
        case replace
    }

    @MainActor
    static func showEmptyTrashConfirmationAlert(itemCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational

        if let trashIcon = NSImage(systemSymbolName: "trash", accessibilityDescription: "Trash") {
            alert.icon = trashIcon
        }

        if itemCount == 0 {
            alert.messageText = "The Trash is empty."
            alert.informativeText = "There are no items to delete."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        } else if itemCount == 1 {
            alert.messageText = "Are you sure you want to permanently erase the item in the Trash?"
        } else {
            alert.messageText = "Are you sure you want to permanently erase the \(itemCount) items in the Trash?"
        }

        alert.informativeText = "You can't undo this action."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    @MainActor
    static func showTrashFileAlert(fileName: String, hasMoreFiles: Bool) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSImage(named: NSImage.cautionName)

        alert.messageText = "The document \"\(fileName)\" can't be opened because it's in the Trash."

        alert.informativeText = "To use this item, first drag it out of the Trash."

        if hasMoreFiles {
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            return response == .alertFirstButtonReturn
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        }
    }
}
