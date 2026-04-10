import AppKit

enum QuitConfirmationPresenter {
    struct Result {
        let shouldQuit: Bool
        let isAlertBeforeQuitEnabled: Bool
    }

    @MainActor
    static func confirmQuit(
        isIndexingInProgress: Bool,
        isAlertBeforeQuitEnabled: Bool,
    ) -> Result {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.showsSuppressionButton = true

        if isIndexingInProgress {
            alert.messageText = "Indexing in Progress"
            alert.informativeText = "Indexing is still running. Quitting now may pause background work."
        } else {
            alert.messageText = "Quit Voyager?"
            alert.informativeText = "Are you sure you want to quit?"
        }

        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        if let suppressionButton = alert.suppressionButton {
            suppressionButton.title = "Alert before app quit"
            suppressionButton.state = isAlertBeforeQuitEnabled ? .on : .off
        }

        let response = alert.runModal()

        let updatedAlertBeforeQuitEnabled: Bool = if let suppressionButton = alert.suppressionButton {
            suppressionButton.state == .on
        } else {
            isAlertBeforeQuitEnabled
        }

        return Result(
            shouldQuit: response == .alertFirstButtonReturn,
            isAlertBeforeQuitEnabled: updatedAlertBeforeQuitEnabled,
        )
    }
}
