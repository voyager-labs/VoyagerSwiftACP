import AppKit
import ComposableArchitecture

extension EntryListTableViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard store.state.entries.renamingItemId != nil else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard (textField.delegate as AnyObject?) === self else { return }
        fsStore.send(.updateRenamingText(textField.stringValue))
    }

    func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard store.state.entries.renamingItemId != nil else { return false }
        guard let textField = control as? NSTextField else { return false }
        guard (textField.delegate as AnyObject?) === self else { return false }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            fsStore.send(.commitRename)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            fsStore.send(.cancelRename)
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            fsStore.send(.commitRename)
            return true
        }

        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard store.state.entries.renamingItemId != nil else { return }
        guard let textField = notification.object as? NSTextField else { return }
        guard (textField.delegate as AnyObject?) === self else { return }
        fsStore.send(.commitRename)
    }
}
