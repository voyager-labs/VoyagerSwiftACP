import AppKit

@MainActor
final class AppKeyboardShortcutMonitor {
    private var keyDownMonitor: Any?

    func start(onSelectContentTab: @escaping (Int) -> Void) {
        stop()

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let position = Self.contentTabPosition(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                modifierFlags: event.modifierFlags,
            ) else {
                return event
            }

            onSelectContentTab(position)
            return nil
        }
    }

    func stop() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }

    static func contentTabPosition(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
    ) -> Int? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let allowedModifiers: NSEvent.ModifierFlags = [.command, .capsLock, .numericPad]

        guard modifiers.contains(.command), modifiers.isSubset(of: allowedModifiers),
              let charactersIgnoringModifiers,
              charactersIgnoringModifiers.count == 1,
              let position = Int(charactersIgnoringModifiers),
              (1 ... 9).contains(position)
        else {
            return nil
        }

        return position
    }
}
