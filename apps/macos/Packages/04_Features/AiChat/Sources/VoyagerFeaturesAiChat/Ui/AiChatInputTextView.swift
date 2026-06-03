import AppKit
import SwiftUI

struct AiChatInputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat

    let isDisabled: Bool
    let maxVisibleHeight: CGFloat
    let onSubmit: () -> Void
    let onAttachmentsDropped: ([URL]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AttachmentDroppingTextView()
        let scrollView = NSScrollView()
        scrollView.documentView = textView

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

    private func configure(textView: AttachmentDroppingTextView, coordinator: Coordinator) {
        textView.delegate = coordinator
        textView.onAttachmentsDropped = { [weak coordinator] urls in
            coordinator?.handleAttachmentsDropped(urls)
        }
        textView.registerForDraggedTypes([.fileURL, .URL])
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

    final class AttachmentDroppingTextView: NSTextView {
        var onAttachmentsDropped: (([URL]) -> Void)?

        init() {
            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(containerSize: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ))
            textContainer.widthTracksTextView = false
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)
            super.init(frame: .zero, textContainer: textContainer)
            minSize = .zero
            maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            let urls = Coordinator.fileURLs(from: sender.draggingPasteboard)
            guard !urls.isEmpty else { return super.draggingEntered(sender) }
            return .copy
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            let urls = Coordinator.fileURLs(from: sender.draggingPasteboard)
            guard !urls.isEmpty else { return super.draggingUpdated(sender) }
            return .copy
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            consumeFileURLs(from: sender.draggingPasteboard) || super.performDragOperation(sender)
        }

        @discardableResult
        func consumeFileURLs(from pasteboard: NSPasteboard) -> Bool {
            let urls = Coordinator.fileURLs(from: pasteboard)
            guard !urls.isEmpty else { return false }

            onAttachmentsDropped?(urls)
            return true
        }
    }

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

        @MainActor
        func textView(
            _ textView: NSTextView,
            readSelectionFrom pasteboard: NSPasteboard,
            type _: NSPasteboard.PasteboardType
        ) -> Bool {
            let urls = Self.fileURLs(from: pasteboard)
            guard !urls.isEmpty else { return false }

            handleAttachmentsDropped(urls)
            return true
        }

        @MainActor
        func handleAttachmentsDropped(_ urls: [URL]) {
            parent.onAttachmentsDropped(urls)
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

        static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
            var urls: [URL] = []

            if let objectURLs = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] {
                urls.append(contentsOf: objectURLs)
            }

            for type in [NSPasteboard.PasteboardType.fileURL, .URL] {
                if let value = pasteboard.string(forType: type), let url = URL(string: value), url.isFileURL {
                    urls.append(url)
                }
            }

            if let fileList = pasteboard.propertyList(forType: .fileURL) as? [String] {
                urls.append(contentsOf: fileList.map(URL.init(fileURLWithPath:)))
            }

            return normalizedUniqueFileURLs(from: urls)
        }

        private static func normalizedUniqueFileURLs(from urls: [URL]) -> [URL] {
            var seenPaths: Set<String> = []
            var normalizedURLs: [URL] = []

            for url in urls where url.isFileURL {
                let normalizedURL = url.standardizedFileURL
                let path = normalizedURL.path(percentEncoded: false)
                guard !path.isEmpty, seenPaths.insert(path).inserted else { continue }
                normalizedURLs.append(normalizedURL)
            }

            return normalizedURLs
        }
    }
}
