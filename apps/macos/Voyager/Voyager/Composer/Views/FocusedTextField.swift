import SwiftUI

struct FocusedTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    var onCommit: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.isBordered = false
        field.drawsBackground = false
        field.isBezeled = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commit)
        field.cell?.sendsActionOnEndEditing = true

        DispatchQueue.main.async { [weak field] in
            guard let field, isFirstResponder else { return }
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context _: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        guard let window = nsView.window else { return }

        if isFirstResponder, window.firstResponder !== nsView {
            window.makeFirstResponder(nsView)
            DispatchQueue.main.async {
                if window.firstResponder !== nsView {
                    window.makeFirstResponder(nsView)
                }
                isFirstResponder = window.firstResponder === nsView
            }
            return
        }

        DispatchQueue.main.async {
            isFirstResponder = nsView.window?.firstResponder == nsView
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onCommit: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            _text = text
            self.onCommit = onCommit
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                text = field.stringValue
            }
        }

        func control(
            _: NSControl,
            textView _: NSTextView,
            doCommandBy commandSelector: Selector,
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
                commandSelector == #selector(NSResponder.insertLineBreak(_:))
            {
                onCommit()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard
                let movement = obj.userInfo?["NSTextMovement"] as? Int,
                movement == NSReturnTextMovement
            else { return }
            onCommit()
        }

        @objc
        func commit() {
            onCommit()
        }
    }
}
