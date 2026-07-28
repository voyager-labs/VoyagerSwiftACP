import AppKit
import Carbon.HIToolbox

@MainActor
final class AppKeyboardShortcutMonitor {
    struct ContentTabShortcutContext: Equatable {
        let hasFocusedWindow: Bool
        let isComposerPresented: Bool

        static let unavailable = Self(
            hasFocusedWindow: false,
            isComposerPresented: false,
        )
    }

    private var keyDownMonitor: Any?

    func start(
        context: @escaping () -> ContentTabShortcutContext,
        onSelectContentTab: @escaping (Int) -> Void,
    ) {
        stop()

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return Self.processKeyDownEvent(
                event,
                context: context(),
                firstResponder: event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder,
                onSelectContentTab: onSelectContentTab,
            )
        }
    }

    func stop() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }

    static func processKeyDownEvent(
        _ event: NSEvent,
        context: ContentTabShortcutContext,
        firstResponder: NSResponder?,
        onSelectContentTab: (Int) -> Void,
    ) -> NSEvent? {
        let handled = handleKeyDown(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            context: context,
            firstResponder: firstResponder,
            onSelectContentTab: onSelectContentTab,
        )
        return handled ? nil : event
    }

    @discardableResult
    static func handleKeyDown(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        context: ContentTabShortcutContext,
        firstResponder: NSResponder?,
        onSelectContentTab: (Int) -> Void,
    ) -> Bool {
        guard context.hasFocusedWindow,
              !context.isComposerPresented,
              !isTextEditingResponder(firstResponder),
              let position = contentTabPosition(
                  keyCode: keyCode,
                  modifierFlags: modifierFlags,
              )
        else {
            return false
        }

        onSelectContentTab(position)
        return true
    }

    static func contentTabPosition(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
    ) -> Int? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let allowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .capsLock, .numericPad]
        guard modifiers.contains(.command), modifiers.isSubset(of: allowedModifiers) else { return nil }

        return contentTabPositionsByKeyCode[keyCode]
    }

    private static let contentTabPositionsByKeyCode: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 1,
        UInt16(kVK_ANSI_Keypad1): 1,
        UInt16(kVK_ANSI_2): 2,
        UInt16(kVK_ANSI_Keypad2): 2,
        UInt16(kVK_ANSI_3): 3,
        UInt16(kVK_ANSI_Keypad3): 3,
        UInt16(kVK_ANSI_4): 4,
        UInt16(kVK_ANSI_Keypad4): 4,
        UInt16(kVK_ANSI_5): 5,
        UInt16(kVK_ANSI_Keypad5): 5,
        UInt16(kVK_ANSI_6): 6,
        UInt16(kVK_ANSI_Keypad6): 6,
        UInt16(kVK_ANSI_7): 7,
        UInt16(kVK_ANSI_Keypad7): 7,
        UInt16(kVK_ANSI_8): 8,
        UInt16(kVK_ANSI_Keypad8): 8,
        UInt16(kVK_ANSI_9): 9,
        UInt16(kVK_ANSI_Keypad9): 9,
    ]

    private static func isTextEditingResponder(_ responder: NSResponder?) -> Bool {
        responder is NSTextView || responder is NSTextField
    }
}
