import AppKit

final class ComposerNativeMenuSearchRow: NSView {
    private let inputField: ComposerNativeMenuSearchField

    var searchField: NSTextField {
        inputField
    }

    init(placeholder: String, delegate: NSTextFieldDelegate) {
        inputField = ComposerNativeMenuSearchField()
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 24))

        let searchCell = NSTextFieldCell(textCell: "")
        searchCell.isBordered = false
        searchCell.isBezeled = false
        searchCell.drawsBackground = false
        searchCell.backgroundColor = .clear
        searchCell.focusRingType = .none
        searchCell.isEditable = true
        searchCell.isSelectable = true

        inputField.placeholderString = placeholder
        inputField.cell = searchCell
        inputField.delegate = delegate
        inputField.isEditable = true
        inputField.isSelectable = true
        inputField.isEnabled = true
        inputField.usesSingleLineMode = true
        inputField.isBordered = false
        inputField.isBezeled = false
        inputField.drawsBackground = false
        inputField.backgroundColor = .clear
        inputField.focusRingType = .none
        inputField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(inputField)
        NSLayoutConstraint.activate([
            inputField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            inputField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func focusSearchField(in window: NSWindow?) {
        if let window {
            window.makeFirstResponder(inputField)
        } else {
            inputField.becomeFirstResponder()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ComposerNativeMenuSearchField: NSTextField {
    override var acceptsFirstResponder: Bool {
        true
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        guard let fieldEditor = currentEditor() as? NSTextView else { return true }
        fieldEditor.drawsBackground = false
        fieldEditor.backgroundColor = .clear
        return true
    }
}
