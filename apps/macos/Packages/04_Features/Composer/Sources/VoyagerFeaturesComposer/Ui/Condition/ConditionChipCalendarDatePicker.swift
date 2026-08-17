import AppKit
import SwiftUI

struct CalendarDatePicker: NSViewRepresentable {
    @Binding var selection: Date
    let onCommit: () -> Void

    final class Coordinator: NSObject {
        @Binding var selection: Date
        let onCommit: () -> Void

        init(selection: Binding<Date>, onCommit: @escaping () -> Void) {
            _selection = selection
            self.onCommit = onCommit
        }

        @MainActor
        @objc
        func dateChanged(_ sender: NSDatePicker) {
            selection = sender.dateValue
            if NSApp.currentEvent?.clickCount == 2 {
                onCommit()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, onCommit: onCommit)
    }

    final class CenteredCalendarContainer: NSView {
        let picker = NSDatePicker()

        override var isFlipped: Bool {
            true
        }

        override var intrinsicContentSize: NSSize {
            picker.fittingSize
        }

        override func layout() {
            super.layout()
            let size = picker.fittingSize
            picker.frame = CGRect(origin: .zero, size: size)
        }
    }

    func makeNSView(context: Context) -> CenteredCalendarContainer {
        let container = CenteredCalendarContainer()
        let picker = container.picker
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = [.yearMonthDay]
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        picker.dateValue = selection

        container.addSubview(picker)
        container.invalidateIntrinsicContentSize()
        return container
    }

    func updateNSView(_ nsView: CenteredCalendarContainer, context _: Context) {
        let picker = nsView.picker
        if picker.dateValue != selection {
            picker.dateValue = selection
        }
        nsView.invalidateIntrinsicContentSize()
        nsView.needsLayout = true
    }
}
