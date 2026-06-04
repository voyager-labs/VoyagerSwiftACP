import AppKit
import SwiftUI

struct RelativePresetMenuPicker: NSViewRepresentable {
    @Binding var selection: DateValueState.RelativePreset
    let width: CGFloat

    final class Coordinator: NSObject {
        var selection: Binding<DateValueState.RelativePreset>

        init(selection: Binding<DateValueState.RelativePreset>) {
            self.selection = selection
        }

        @MainActor
        @objc
        func selectionChanged(_ sender: NSPopUpButton) {
            guard sender.indexOfSelectedItem >= 0 else { return }
            selection.wrappedValue = DateValueState.RelativePreset.allCases[sender.indexOfSelectedItem]
        }
    }

    final class FixedWidthPopUpContainer: NSView {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        var preferredWidth: CGFloat

        init(width: CGFloat) {
            preferredWidth = width
            super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override var isFlipped: Bool {
            true
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: preferredWidth, height: button.intrinsicContentSize.height)
        }

        override func layout() {
            super.layout()
            button.frame = bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> FixedWidthPopUpContainer {
        let container = FixedWidthPopUpContainer(width: width)
        configure(container.button, coordinator: context.coordinator)
        container.addSubview(container.button)
        container.invalidateIntrinsicContentSize()
        return container
    }

    func updateNSView(_ nsView: FixedWidthPopUpContainer, context: Context) {
        context.coordinator.selection = $selection
        nsView.preferredWidth = width
        configure(nsView.button, coordinator: context.coordinator)
        nsView.invalidateIntrinsicContentSize()
        nsView.needsLayout = true
    }

    private func configure(_ button: NSPopUpButton, coordinator: Coordinator) {
        button.removeAllItems()
        button.addItems(withTitles: DateValueState.RelativePreset.allCases.map(\.menuTitle))
        button.selectItem(at: DateValueState.RelativePreset.allCases.firstIndex(of: selection) ?? 0)
        button.target = coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.controlSize = .regular
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
}

private extension DateValueState.RelativePreset {
    var menuTitle: String {
        switch self {
        case .custom:
            "Custom"
        case .today:
            "Today"
        case .yesterday:
            "Yesterday"
        case .daysAgo7:
            "7 days ago"
        case .daysAgo30:
            "30 days ago"
        case .monthsAgo3:
            "3 months ago"
        case .yearAgo1:
            "1 year ago"
        }
    }
}
