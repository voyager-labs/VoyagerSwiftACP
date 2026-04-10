import AppKit
import Combine

@MainActor
final class ComposerKeyboardMonitor: ObservableObject {
    @Published private(set) var isOptionKeyPressed: Bool = false

    private var keyDownMonitor: Any?
    private var flagsChangedMonitor: Any?

    private let escapeKeyCode: UInt16 = 53
    private let zKeyCode: UInt16 = 6

    func start(
        onEscape: @escaping () -> Bool,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void,
    ) {
        stop()
        isOptionKeyPressed = NSEvent.modifierFlags.contains(.option)

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == escapeKeyCode {
                return onEscape() ? nil : event
            }

            if event.keyCode == zKeyCode, event.modifierFlags.contains(.command) {
                if event.modifierFlags.contains(.shift) {
                    onRedo()
                } else {
                    onUndo()
                }
                return nil
            }

            return event
        }

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.isOptionKeyPressed = event.modifierFlags.contains(.option)
            return event
        }
    }

    func stop() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
    }
}
