import AppKit
import Carbon.HIToolbox
import VoyagerPagesFileManager

@MainActor
final class AppKeyboardShortcutMonitor {
    enum ControlTabGestureCommand: Equatable {
        case immediateMostRecentlyUsed
        case presentSwitcher
        case moveNext
        case movePrevious
        case activateSwitcherSelection
        case dismissSwitcher
    }

    struct HoldScheduler {
        let schedule: (TimeInterval, @escaping () -> Void) -> Void
    }

    private enum ControlTabGestureState {
        case idle
        case pending(
            timestamp: TimeInterval,
            generation: UInt64,
            ownerWindowID: WindowManagerState.WindowID?,
        )
        case overlayOwned(
            generation: UInt64,
            ownerWindowID: WindowManagerState.WindowID?,
            source: FileManagerContentTabSwitcherPresentation.Source,
        )
    }

    struct ContentTabShortcutContext: Equatable {
        let hasFocusedWindow: Bool
        let isComposerPresented: Bool
        let isContentTabSwitcherPresented: Bool
        let focusedWindowID: WindowManagerState.WindowID?
        let contentTabSwitcherSource: FileManagerContentTabSwitcherPresentation.Source?

        init(
            hasFocusedWindow: Bool,
            isComposerPresented: Bool,
            isContentTabSwitcherPresented: Bool = false,
            focusedWindowID: WindowManagerState.WindowID? = nil,
            contentTabSwitcherSource: FileManagerContentTabSwitcherPresentation.Source? = nil,
        ) {
            self.hasFocusedWindow = hasFocusedWindow
            self.isComposerPresented = isComposerPresented
            self.isContentTabSwitcherPresented = isContentTabSwitcherPresented
            self.focusedWindowID = focusedWindowID
            self.contentTabSwitcherSource = contentTabSwitcherSource
        }

        static let unavailable = Self(
            hasFocusedWindow: false,
            isComposerPresented: false,
            isContentTabSwitcherPresented: false,
        )
    }

    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsChangedMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var overlayDismiss: (() -> Void)?
    private var targetedCommand: ((WindowManagerState.WindowID, ControlTabGestureCommand) -> Void)?
    private var controlTabState: ControlTabGestureState = .idle
    private var generation: UInt64 = 0
    private let holdScheduler: HoldScheduler

    private static let holdThreshold: TimeInterval = 0.250
    private static let tabKeyCode = UInt16(kVK_Tab)

    init(holdScheduler: HoldScheduler = .live) {
        self.holdScheduler = holdScheduler
    }

    func start(
        context: @escaping () -> ContentTabShortcutContext,
        onSelectContentTab: @escaping (Int) -> Void,
    ) {
        stop()
        overlayDismiss = nil
        targetedCommand = nil

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self != nil else { return event }
            return Self.processKeyDownEvent(
                event,
                context: context(),
                firstResponder: event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder,
                onSelectContentTab: onSelectContentTab,
            )
        }
    }

    func start(
        context: @escaping () -> ContentTabShortcutContext,
        onCommand: @escaping (ControlTabGestureCommand) -> Void,
        onTargetedCommand: ((WindowManagerState.WindowID, ControlTabGestureCommand) -> Void)? = nil,
        onSelectContentTab: @escaping (Int) -> Void = { _ in },
    ) {
        stop()
        targetedCommand = onTargetedCommand
        overlayDismiss = { [weak self] in
            self?.emitControlTabCommand(.dismissSwitcher, fallback: onCommand)
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if let position = Self.contentTabPosition(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
            ), isContentTabContextAllowed(
                context(),
                firstResponder: event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder,
            ) {
                onSelectContentTab(position)
                return nil
            }
            return handleKeyDownEvent(
                event,
                context: context(),
                firstResponder: event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder,
                emit: onCommand,
                latestContext: context,
                latestFirstResponder: { NSApp.keyWindow?.firstResponder },
            )
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            return handleKeyUpEvent(
                event,
                context: context(),
                firstResponder: NSApp.keyWindow?.firstResponder ?? event.window?.firstResponder,
                emit: onCommand,
            )
        }
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            return handleFlagsChangedEvent(
                event,
                context: context(),
                firstResponder: NSApp.keyWindow?.firstResponder ?? event.window?.firstResponder,
                emit: onCommand,
            )
        }
        observeApplicationResignation()
    }

    func stop() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }
        if let flagsChangedMonitor {
            NSEvent.removeMonitor(flagsChangedMonitor)
            self.flagsChangedMonitor = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
        cancelControlTabGesture()
    }

    func applicationDidResignActive() {
        cancelControlTabGesture()
    }

    @discardableResult
    func handleKeyDownEvent(
        _ event: NSEvent,
        context: ContentTabShortcutContext,
        firstResponder: NSResponder?,
        emit: @escaping (ControlTabGestureCommand) -> Void,
        latestContext: (() -> ContentTabShortcutContext)? = nil,
        latestFirstResponder: (() -> NSResponder?)? = nil,
    ) -> NSEvent? {
        overlayDismiss = { [weak self] in
            self?.emitControlTabCommand(.dismissSwitcher, fallback: emit)
        }
        guard Self.isExactControlTab(modifierFlags: event.modifierFlags), event.keyCode == Self.tabKeyCode else {
            if event.keyCode == Self.tabKeyCode {
                cancelControlTabGesture(emit: emit)
            }
            return event
        }
        guard isContentTabContextAllowed(context, firstResponder: firstResponder) else {
            cancelControlTabGesture(emit: emit)
            return event
        }

        resetStaleOverlayOwner(context: context)

        switch controlTabState {
        case .idle:
            guard !event.isARepeat else { return nil }
            generation &+= 1
            let token = generation
            controlTabState = .pending(
                timestamp: event.timestamp,
                generation: token,
                ownerWindowID: context.focusedWindowID,
            )
            let readLatestContext = latestContext ?? { context }
            let readLatestFirstResponder = latestFirstResponder ?? { firstResponder }
            holdScheduler.schedule(Self.holdThreshold) { [weak self] in
                guard let self else { return }
                fireHold(
                    generation: token,
                    context: readLatestContext(),
                    firstResponder: readLatestFirstResponder(),
                    emit: emit,
                )
            }
        case .pending:
            break
        case .overlayOwned:
            emitControlTabCommand(
                event.modifierFlags.contains(.shift) ? .movePrevious : .moveNext,
                fallback: emit,
            )
        }
        return nil
    }

    private func observeApplicationResignation() {
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applicationDidResignActive()
            }
        }
    }

    private func resetStaleOverlayOwner(context: ContentTabShortcutContext) {
        guard case let .overlayOwned(_, ownerWindowID, source) = controlTabState,
              let ownerWindowID,
              ownerWindowID != context.focusedWindowID ||
              !context.isContentTabSwitcherPresented ||
              context.contentTabSwitcherSource != source
        else { return }
        generation &+= 1
        controlTabState = .idle
    }

    @discardableResult
    func handleKeyUpEvent(
        _ event: NSEvent,
        context: ContentTabShortcutContext,
        firstResponder: NSResponder? = nil,
        emit: @escaping (ControlTabGestureCommand) -> Void,
    ) -> NSEvent? {
        overlayDismiss = { [weak self] in
            self?.emitControlTabCommand(.dismissSwitcher, fallback: emit)
        }
        guard Self.isExactControlTab(modifierFlags: event.modifierFlags), event.keyCode == Self.tabKeyCode else {
            if event.keyCode == Self.tabKeyCode {
                cancelControlTabGesture(emit: emit)
            }
            return event
        }
        guard isContentTabContextAllowed(context, firstResponder: firstResponder) else {
            cancelControlTabGesture(emit: emit)
            return event
        }

        switch controlTabState {
        case .pending:
            completePendingGesture(
                timestamp: event.timestamp,
                context: context,
                firstResponder: firstResponder,
                dismissHold: false,
                emit: emit,
            )
        case .overlayOwned:
            break
        case .idle:
            return event
        }
        return nil
    }

    private func pendingOwnerMatches(_ context: ContentTabShortcutContext) -> Bool {
        guard case let .pending(_, _, ownerWindowID) = controlTabState else { return false }
        return ownerWindowID == context.focusedWindowID
    }

    @discardableResult
    func handleFlagsChangedEvent(
        _ event: NSEvent,
        context: ContentTabShortcutContext,
        firstResponder: NSResponder? = nil,
        emit: @escaping (ControlTabGestureCommand) -> Void,
    ) -> NSEvent? {
        overlayDismiss = { [weak self] in
            self?.emitControlTabCommand(.dismissSwitcher, fallback: emit)
        }
        guard isContentTabContextAllowed(context, firstResponder: nil) else {
            cancelControlTabGesture(emit: emit)
            return event
        }
        let wasActive = switch controlTabState {
        case .idle:
            false
        case .pending, .overlayOwned:
            true
        }
        guard Self.isExactControlTab(modifierFlags: event.modifierFlags) else {
            if case .pending = controlTabState,
               !event.modifierFlags.contains(.control)
            {
                completePendingGesture(
                    timestamp: event.timestamp,
                    context: context,
                    firstResponder: firstResponder,
                    dismissHold: true,
                    emit: emit,
                )
            } else if case .overlayOwned = controlTabState,
                      !event.modifierFlags.contains(.control)
            {
                activateOwnedSwitcherSelection(context: context, emit: emit)
            } else if wasActive {
                cancelControlTabGesture(emit: emit)
            }
            return wasActive ? nil : event
        }
        return event
    }

    private func completePendingGesture(
        timestamp: TimeInterval,
        context: ContentTabShortcutContext,
        firstResponder: NSResponder?,
        dismissHold: Bool,
        emit: @escaping (ControlTabGestureCommand) -> Void,
    ) {
        guard case let .pending(startTimestamp, token, _) = controlTabState else { return }
        if timestamp - startTimestamp < Self.holdThreshold {
            let canSwitchMRU = isContentTabContextAllowed(context, firstResponder: firstResponder)
                && pendingOwnerMatches(context)
                && !context.isContentTabSwitcherPresented
                && context.contentTabSwitcherSource == nil
            cancelControlTabGesture()
            if canSwitchMRU {
                emitControlTabCommand(.immediateMostRecentlyUsed, fallback: emit)
            }
            return
        }

        fireHold(
            generation: token,
            context: context,
            firstResponder: firstResponder,
            emit: emit,
        )
        if dismissHold, case .overlayOwned = controlTabState {
            cancelControlTabGesture(emit: emit)
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

    private func fireHold(
        generation token: UInt64,
        context: ContentTabShortcutContext,
        firstResponder: NSResponder?,
        emit: @escaping (ControlTabGestureCommand) -> Void,
    ) {
        guard case let .pending(_, currentToken, ownerWindowID) = controlTabState,
              currentToken == token
        else {
            return
        }
        guard isContentTabContextAllowed(context, firstResponder: firstResponder),
              ownerWindowID == context.focusedWindowID,
              !context.isContentTabSwitcherPresented,
              context.contentTabSwitcherSource == nil
        else {
            generation &+= 1
            controlTabState = .idle
            return
        }
        controlTabState = .overlayOwned(
            generation: token,
            ownerWindowID: ownerWindowID,
            source: .keyboardShortcut,
        )
        emitControlTabCommand(.presentSwitcher, fallback: emit)
    }

    private func cancelControlTabGesture(emit: ((ControlTabGestureCommand) -> Void)? = nil) {
        if case .overlayOwned = controlTabState {
            if let emit {
                emitControlTabCommand(.dismissSwitcher, fallback: emit)
            } else {
                overlayDismiss?()
            }
        }
        generation &+= 1
        controlTabState = .idle
    }

    private func activateOwnedSwitcherSelection(
        context: ContentTabShortcutContext,
        emit: @escaping (ControlTabGestureCommand) -> Void,
    ) {
        guard case let .overlayOwned(_, ownerWindowID, source) = controlTabState,
              source == .keyboardShortcut,
              ownerWindowID == context.focusedWindowID,
              context.isContentTabSwitcherPresented,
              context.contentTabSwitcherSource == source
        else {
            cancelControlTabGesture(emit: emit)
            return
        }
        emitControlTabCommand(.activateSwitcherSelection, fallback: emit)
        generation &+= 1
        controlTabState = .idle
    }

    private func emitControlTabCommand(
        _ command: ControlTabGestureCommand,
        fallback: (ControlTabGestureCommand) -> Void,
    ) {
        let ownerWindowID: WindowManagerState.WindowID? = switch controlTabState {
        case let .pending(_, _, ownerWindowID), let .overlayOwned(_, ownerWindowID, _): ownerWindowID
        case .idle: nil
        }
        guard command != .immediateMostRecentlyUsed,
              let ownerWindowID,
              let targetedCommand
        else {
            fallback(command)
            return
        }
        targetedCommand(ownerWindowID, command)
    }

    private func isContentTabContextAllowed(
        _ context: ContentTabShortcutContext,
        firstResponder: NSResponder?,
    ) -> Bool {
        context.hasFocusedWindow && !context.isComposerPresented && !Self.isTextEditingResponder(firstResponder)
    }

    private static func isExactControlTab(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let modifiers = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        return modifiers == [.control] || modifiers == [.control, .shift]
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

private extension AppKeyboardShortcutMonitor.HoldScheduler {
    static let live = Self { delay, callback in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: callback)
    }
}
