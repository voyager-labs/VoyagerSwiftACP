import AppKit
import SwiftUI

struct AutoSizingTextView: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let textAlignment: NSTextAlignment
    let availableWidth: CGFloat
    let shouldFocus: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> AutoSizingTextViewContainer {
        let textView = AutoSizingTextViewInner()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.font = font
        textView.textColor = .labelColor
        textView.onCommit = onCommit
        textView.onCancel = onCancel
        textView.applyAlignment(textAlignment)

        let container = AutoSizingTextViewContainer(textView: textView)
        container.setText(text)
        return container
    }

    func updateNSView(_ nsView: AutoSizingTextViewContainer, context _: Context) {
        if nsView.textView.string != text {
            nsView.setText(text)
        }

        nsView.availableWidth = availableWidth
        nsView.textView.font = font
        nsView.textView.onCommit = onCommit
        nsView.textView.onCancel = onCancel
        nsView.textView.applyAlignment(textAlignment)

        if shouldFocus {
            nsView.focusIfNeeded()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

final class AutoSizingTextViewContainer: NSView {
    let textView: AutoSizingTextViewInner
    var availableWidth: CGFloat = 0 {
        didSet {
            if abs(oldValue - availableWidth) > 0.5 {
                invalidateIntrinsicContentSize()
            }
        }
    }

    init(textView: AutoSizingTextViewInner) {
        self.textView = textView
        super.init(frame: .zero)
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        textView.frame = bounds
        let width = availableWidth > 1 ? availableWidth : bounds.width
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        guard let font = textView.font else {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        let width = max(availableWidth, 1)
        let fallbackLineHeight = ceil(font.ascender - font.descender + font.leading)
        let lineHeight = ceil(textView.layoutManager?.defaultLineHeight(for: font) ?? fallbackLineHeight)
        if width <= 1 {
            return NSSize(width: width, height: max(lineHeight, fallbackLineHeight))
        }

        let paragraphStyle = (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? {
            let style = NSMutableParagraphStyle()
            style.alignment = textView.alignment
            style.lineBreakMode = .byWordWrapping
            return style
        }()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]

        let text = textView.string as NSString
        let bounding = text.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
        )
        let height = max(max(lineHeight, fallbackLineHeight), ceil(bounding.height))
        return NSSize(width: width, height: height)
    }

    func setText(_ value: String) {
        textView.string = value
        invalidateIntrinsicContentSize()
    }

    func focusIfNeeded() {
        if window?.firstResponder != textView {
            window?.makeFirstResponder(textView)
            textView.selectFilenameBase()
        }
    }
}

final class AutoSizingTextViewInner: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            selectFilenameBase()
        }
        return became
    }

    func selectFilenameBase() {
        let value = string as NSString
        let base = value.deletingPathExtension as NSString
        guard base.length > 0, base.isEqual(to: value as String) == false else {
            selectAll(nil)
            return
        }
        setSelectedRange(NSRange(location: 0, length: base.length))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        if event.keyCode == 36,
           event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
        {
            onCommit?()
            return
        }

        super.keyDown(with: event)
    }
}

private extension NSTextView {
    func applyAlignment(_ alignment: NSTextAlignment) {
        let paragraphStyle = (typingAttributes[.paragraphStyle] as? NSMutableParagraphStyle) ??
            NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        typingAttributes[.paragraphStyle] = paragraphStyle

        if let textStorage {
            textStorage.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: NSRange(location: 0, length: textStorage.length),
            )
        }
    }
}
