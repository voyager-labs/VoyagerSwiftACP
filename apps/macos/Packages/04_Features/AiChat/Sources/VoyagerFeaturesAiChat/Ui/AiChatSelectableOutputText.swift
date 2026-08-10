import AppKit
import SwiftUI

struct AiChatSelectableOutputText: NSViewRepresentable {
    enum SizingMode {
        case expandsToFillWidth
        case fitsContent
    }

    let blockID: AiChatMarkdownDocument.BlockID
    let attributedText: NSAttributedString
    var renderSession: AiChatAssistantMarkdownRenderSession?
    var transcriptRow: AiChatTranscriptRowDiscriminator?
    var allowsHorizontalOverflow: Bool
    var sizingMode: SizingMode
    var accessibilityLabel: String?
    var accessibilityValue: String?
    var contextMenuActions: [AiChatOutputContextMenuAction]

    init(
        blockID: AiChatMarkdownDocument.BlockID,
        attributedText: NSAttributedString,
        renderSession: AiChatAssistantMarkdownRenderSession? = nil,
        transcriptRow: AiChatTranscriptRowDiscriminator? = nil,
        allowsHorizontalOverflow: Bool = false,
        sizingMode: SizingMode = .expandsToFillWidth,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil,
        contextMenuActions: [AiChatOutputContextMenuAction] = [],
    ) {
        self.blockID = blockID
        self.attributedText = attributedText
        self.renderSession = renderSession
        self.transcriptRow = transcriptRow
        self.allowsHorizontalOverflow = allowsHorizontalOverflow
        self.sizingMode = sizingMode
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.contextMenuActions = contextMenuActions
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_: NSScrollView, context: Context) {
        context.coordinator.update(
            blockID: blockID,
            attributedText: attributedText,
            renderSession: renderSession,
            transcriptRow: transcriptRow,
            allowsHorizontalOverflow: allowsHorizontalOverflow,
            sizingMode: sizingMode,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: accessibilityValue,
            contextMenuActions: contextMenuActions,
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context _: Context) -> CGSize? {
        guard let scrollView = nsView as? IntrinsicTextScrollView else { return nil }
        let naturalWidth = max(scrollView.naturalContentWidth, 0)
        let proposedWidth = proposal.width

        let resolvedWidth: CGFloat
        switch sizingMode {
        case .expandsToFillWidth:
            guard let proposed = proposedWidth, proposed.isFinite, proposed > 0 else { return nil }
            resolvedWidth = proposed
        case .fitsContent:
            if let proposed = proposedWidth, proposed.isFinite, proposed > 0 {
                resolvedWidth = min(naturalWidth, proposed)
            } else {
                resolvedWidth = naturalWidth
            }
        }

        let height = scrollView.measuredHeight(at: resolvedWidth)
        return CGSize(width: resolvedWidth, height: height)
    }

    static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        coordinator.prepareForDismantle()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let textView: OutputTextView
        let scrollView: IntrinsicTextScrollView

        private var blockID: AiChatMarkdownDocument.BlockID?
        private weak var renderSession: AiChatAssistantMarkdownRenderSession?
        private var transcriptRow: AiChatTranscriptRowDiscriminator?

        override init() {
            textView = OutputTextView()
            scrollView = IntrinsicTextScrollView(textView: textView)
            super.init()
            textView.delegate = self
            textView.onSelectionContextChanged = { [weak self] in
                self?.captureSelection()
            }
        }

        func update(
            blockID newBlockID: AiChatMarkdownDocument.BlockID,
            attributedText: NSAttributedString,
            renderSession newRenderSession: AiChatAssistantMarkdownRenderSession? = nil,
            transcriptRow newTranscriptRow: AiChatTranscriptRowDiscriminator? = nil,
            allowsHorizontalOverflow: Bool = false,
            sizingMode: AiChatSelectableOutputText.SizingMode = .expandsToFillWidth,
            accessibilityLabel: String? = nil,
            accessibilityValue: String? = nil,
            contextMenuActions: [AiChatOutputContextMenuAction] = [],
        ) {
            captureSelection()
            let hasStableIdentity = blockID == newBlockID
            let selection = AiChatMarkdownDocument.PlainSelectionRange(textView.selectedRange())
            let wasFirstResponder = hasStableIdentity && textView.window?.firstResponder === textView
            renderSession = newRenderSession
            transcriptRow = newTranscriptRow

            textView.suppressesSelectionContextChanges = true
            defer { textView.suppressesSelectionContextChanges = false }
            textView.textStorage?.setAttributedString(attributedText)
            textView.contextMenuActions = contextMenuActions
            scrollView.configureHorizontalOverflow(allowsHorizontalOverflow)
            scrollView.configureSizingMode(sizingMode)
            blockID = newBlockID

            let sessionRestoration = newTranscriptRow.flatMap { row in
                newRenderSession?.restoration(presentationID: newBlockID, transcriptRow: row)
            }
            let restoredSelection = sessionRestoration?.selection ?? selection
            if hasStableIdentity || sessionRestoration != nil,
               let restoredSelection,
               let searchRange = restoredSelection.searchRange(
                   in: textView.string,
                   invalidRangePolicy: .clamp,
               ),
               let validSelection = searchRange.plainSelectionRange(in: textView.string)
            {
                textView.setSelectedRange(validSelection.nsRange)
            } else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }

            textView.setAccessibilityLabel(accessibilityLabel)
            textView.setAccessibilityValue(accessibilityValue ?? textView.string)
            scrollView.updateDocumentGeometry()

            if wasFirstResponder || sessionRestoration?.isFirstResponder == true {
                textView.window?.makeFirstResponder(textView)
            }
        }

        func textViewDidChangeSelection(_: Notification) {
            captureSelection()
        }

        func prepareForDismantle() {
            captureSelection()
            textView.suppressesSelectionContextChanges = true
        }

        func captureSelection() {
            guard !textView.suppressesSelectionContextChanges else { return }
            let selection = AiChatMarkdownDocument.PlainSelectionRange(textView.selectedRange())
            let isFirstResponder = textView.window?.firstResponder === textView
            guard let blockID, let renderSession, let transcriptRow else { return }
            renderSession.captureSelection(
                presentationID: blockID,
                transcriptRow: transcriptRow,
                selection: selection,
                isFirstResponder: isFirstResponder,
            )
        }
    }

    final class OutputTextView: NSTextView {
        var onSelectionContextChanged: (() -> Void)?
        var suppressesSelectionContextChanges = false
        var contextMenuActions: [AiChatOutputContextMenuAction] = []

        override var acceptsFirstResponder: Bool {
            isSelectable
        }

        init() {
            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(containerSize: NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude,
            ))
            textContainer.widthTracksTextView = true
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)
            super.init(frame: .zero, textContainer: textContainer)

            isEditable = false
            isSelectable = true
            drawsBackground = false
            isRichText = true
            importsGraphics = false
            isHorizontallyResizable = false
            isVerticallyResizable = true
            autoresizingMask = [.width]
            textContainerInset = .zero
            textContainer.lineFragmentPadding = 0
            minSize = .zero
            maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude,
            )
            setAccessibilityElement(true)
            setAccessibilityRole(.staticText)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func setSelectedRange(_ charRange: NSRange) {
            super.setSelectedRange(charRange)
            if !suppressesSelectionContextChanges { onSelectionContextChanged?() }
        }

        override func becomeFirstResponder() -> Bool {
            let becameFirstResponder = super.becomeFirstResponder()
            if becameFirstResponder, !suppressesSelectionContextChanges { onSelectionContextChanged?() }
            return becameFirstResponder
        }

        override func resignFirstResponder() -> Bool {
            let resignedFirstResponder = super.resignFirstResponder()
            guard resignedFirstResponder, !suppressesSelectionContextChanges else { return resignedFirstResponder }
            // Dismantle 중에는 미리 캡처한 선택 snapshot을 보존한다.
            guard window != nil else { onSelectionContextChanged?()
                return resignedFirstResponder
            }
            let current = selectedRange()
            if current.length > 0 {
                setSelectedRange(NSRange(location: current.location, length: 0))
            } else {
                onSelectionContextChanged?()
            }
            return resignedFirstResponder
        }

        override func setFrameSize(_ newSize: NSSize) {
            let widthChanged = frame.width != newSize.width
            super.setFrameSize(newSize)
            if widthChanged {
                enclosingScrollView?.invalidateIntrinsicContentSize()
            }
        }

        override func responds(to selector: Selector!) -> Bool {
            guard let selector, !Self.isForbiddenEditingSelector(selector) else {
                return false
            }
            if selector == #selector(NSText.copy(_:)) {
                let hasSelection = MainActor.assumeIsolated { selectedRange().length > 0 }
                return hasSelection && super.responds(to: selector)
            }
            if selector == #selector(NSText.selectAll(_:)) {
                let hasContent = MainActor.assumeIsolated { !string.isEmpty }
                return hasContent && super.responds(to: selector)
            }
            return super.responds(to: selector)
        }

        override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
            guard let action = item.action else { return false }

            switch action {
            case #selector(NSText.copy(_:)):
                return selectedRange().length > 0
            case #selector(NSText.selectAll(_:)):
                return !string.isEmpty
            default:
                return Self.isForbiddenEditingSelector(action)
                    ? false
                    : super.validateUserInterfaceItem(item)
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            augmentedContextMenu(from: super.menu(for: event))
        }

        func augmentedContextMenu(from baseMenu: NSMenu?) -> NSMenu {
            let menu = baseMenu ?? NSMenu()
            for item in menu.items where item.tag == Self.contextMenuItemTag {
                menu.removeItem(item)
            }
            guard !contextMenuActions.isEmpty else { return menu }

            let separator = NSMenuItem.separator()
            separator.tag = Self.contextMenuItemTag
            menu.insertItem(separator, at: 0)
            for action in contextMenuActions.reversed() {
                let carrier = AiChatSelectableOutputTextContextMenuActionCarrier(action: action.perform)
                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(AiChatSelectableOutputTextContextMenuActionCarrier.performMenuItemAction(_:)),
                    keyEquivalent: "",
                )
                item.target = carrier
                item.representedObject = carrier
                item.isEnabled = action.isEnabled
                item.tag = Self.contextMenuItemTag
                menu.insertItem(item, at: 0)
            }
            return menu
        }

        override func validRequestor(
            forSendType sendType: NSPasteboard.PasteboardType?,
            returnType: NSPasteboard.PasteboardType?,
        ) -> Any? {
            if sendType == .string, returnType == nil, selectedRange().length > 0 {
                return self
            }
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }

        override func cut(_: Any?) {}

        override func paste(_: Any?) {}

        private static let contextMenuItemTag = 636_001

        nonisolated private static func isForbiddenEditingSelector(_ selector: Selector) -> Bool {
            selector == #selector(NSText.cut(_:))
                || selector == #selector(NSText.paste(_:))
                || selector == NSSelectorFromString("pasteAsPlainText:")
                || selector == NSSelectorFromString("undo:")
                || selector == NSSelectorFromString("redo:")
        }
    }
}

@MainActor
private final class AiChatSelectableOutputTextContextMenuActionCarrier: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc(performMenuItemAction:)
    func performMenuItemAction(_: Any?) {
        action()
    }
}
