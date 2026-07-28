import AppKit
import SwiftUI

struct ComposerAnchoredDropdown<Label: View, Content: View>: View {
    @Binding private var isPresented: Bool
    private let dropdownAccessibilityIdentifier: String
    private let label: Label
    private let content: Content

    init(
        isPresented: Binding<Bool>,
        dropdownAccessibilityIdentifier: String = "composer.property.dropdown",
        @ViewBuilder label: () -> Label,
        @ViewBuilder content: () -> Content,
    ) {
        _isPresented = isPresented
        self.dropdownAccessibilityIdentifier = dropdownAccessibilityIdentifier
        self.label = label()
        self.content = content()
    }

    var body: some View {
        label.background(
            ComposerAnchoredDropdownPresenter(
                isPresented: $isPresented,
                accessibilityIdentifier: dropdownAccessibilityIdentifier,
                content: content,
            ),
        )
    }
}

private struct ComposerAnchoredDropdownPresenter<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let accessibilityIdentifier: String
    let content: Content

    func makeNSView(context: Context) -> ComposerAnchoredDropdownAnchorView {
        context.coordinator.anchorView
    }

    func updateNSView(_ anchorView: ComposerAnchoredDropdownAnchorView, context: Context) {
        context.coordinator.update(
            binding: $isPresented,
            isPresented: isPresented,
            content: content,
            accessibilityIdentifier: accessibilityIdentifier,
            relativeTo: anchorView,
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, content: content)
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        let anchorView = ComposerAnchoredDropdownAnchorView(frame: .zero)
        let popover = NSPopover()
        let contentController: NSHostingController<Content>
        var binding: Binding<Bool>

        init(isPresented: Binding<Bool>, content: Content) {
            binding = isPresented
            contentController = NSHostingController(rootView: content)
            super.init()

            popover.behavior = .transient
            popover.contentViewController = contentController
            popover.delegate = self
        }

        func update(
            binding: Binding<Bool>,
            isPresented: Bool,
            content: Content,
            accessibilityIdentifier: String,
            relativeTo anchorView: NSView,
        ) {
            self.binding = binding
            contentController.rootView = content
            contentController.view.setAccessibilityIdentifier(accessibilityIdentifier)
            contentController.view.layoutSubtreeIfNeeded()
            popover.contentSize = contentController.view.fittingSize

            if isPresented, !popover.isShown {
                popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
            } else if !isPresented, popover.isShown {
                popover.performClose(nil)
            }
        }

        func popoverDidClose(_: Notification) {
            if binding.wrappedValue {
                binding.wrappedValue = false
            }
        }
    }
}

private final class ComposerAnchoredDropdownAnchorView: NSView {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
