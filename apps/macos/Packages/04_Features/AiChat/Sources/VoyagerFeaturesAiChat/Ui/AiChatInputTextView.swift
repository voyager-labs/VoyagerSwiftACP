import AppKit
import SwiftUI

struct AiChatInputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat

    let isDisabled: Bool
    let maxVisibleHeight: CGFloat
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        configure(scrollView: scrollView)
        configure(textView: textView, coordinator: context.coordinator)

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        textView.isEditable = !isDisabled
        textView.textColor = isDisabled ? .disabledControlTextColor : .labelColor
        textView.font = Self.textFont
        updateTextContainerWidth(for: textView, in: scrollView)
        updateMeasuredHeight(for: textView)

        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func configure(scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
    }

    private func configure(textView: NSTextView, coordinator: Coordinator) {
        textView.delegate = coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: Self.textHorizontalInset, height: Self.textVerticalInset)
        textView.font = Self.textFont
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        updateTextContainerWidth(for: textView, in: coordinator.scrollView)
    }

    private func updateTextContainerWidth(for textView: NSTextView, in scrollView: NSScrollView?) {
        let availableWidth = scrollView?.contentSize.width ?? textView.bounds.width
        let textWidth = max(0, availableWidth - Self.trailingReservedWidth)
        textView.textContainer?.containerSize = NSSize(
            width: textWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    fileprivate func updateMeasuredHeight(for textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = ceil(usedRect.height + textView.textContainerInset.height * 2)
        updateScrollerVisibility(height: height, textView: textView)

        DispatchQueue.main.async {
            measuredHeight = height
        }
    }

    private func updateScrollerVisibility(height: CGFloat, textView: NSTextView) {
        textView.enclosingScrollView?.hasVerticalScroller = height > maxVisibleHeight
    }

    private static let textFont = NSFont.systemFont(ofSize: 13)
    static let textHorizontalInset: CGFloat = 0
    static let textVerticalInset: CGFloat = 2

    private static let trailingReservedWidth: CGFloat = 14

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AiChatInputTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(parent: AiChatInputTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.updateTextContainerWidth(for: textView, in: scrollView)
            parent.updateMeasuredHeight(for: textView)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textDidBeginEditing(_: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_: Notification) {
            parent.isFocused = false
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            let modifierFlags = NSApp.currentEvent?.modifierFlags ?? []
            if modifierFlags.contains(.shift) || modifierFlags.contains(.option) {
                textView.insertNewline(nil)
                return true
            }

            parent.onSubmit()
            return true
        }
    }
}
