import AppKit
import ComposableArchitecture
import VoyagerFeaturesAccess

@MainActor private var unlockWindowController: UnlockSurfaceWindowController?

public struct UnlockSurfaceWindowClient: Sendable {
    public var showWindow: @Sendable () async -> Void
    public var closeWindow: @Sendable () async -> Void
    public var openMainWindow: @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool
    public var onUnlocked: @Sendable (_ snapshot: AccessStatusSnapshot) async -> Void

    public nonisolated init(
        showWindow: @escaping @Sendable () async -> Void,
        closeWindow: @escaping @Sendable () async -> Void,
        openMainWindow: @escaping @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool,
        onUnlocked: @escaping @Sendable (_ snapshot: AccessStatusSnapshot) async -> Void = { _ in },
    ) {
        self.showWindow = showWindow
        self.closeWindow = closeWindow
        self.openMainWindow = openMainWindow
        self.onUnlocked = onUnlocked
    }
}

extension UnlockSurfaceWindowClient: DependencyKey {
    public nonisolated static var liveValue: UnlockSurfaceWindowClient {
        UnlockSurfaceWindowClient(
            showWindow: { fatalError("not configured") },
            closeWindow: { fatalError("not configured") },
            openMainWindow: { _ in fatalError("not configured") },
        )
    }

    public nonisolated static var testValue: UnlockSurfaceWindowClient {
        UnlockSurfaceWindowClient(
            showWindow: { fatalError("not configured") },
            closeWindow: { fatalError("not configured") },
            openMainWindow: { _ in fatalError("not configured") },
        )
    }

    public nonisolated static var previewValue: UnlockSurfaceWindowClient { testValue }

    public nonisolated static func makeLive(
        openMainWindow: @escaping @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool,
        onUnlocked: @escaping @Sendable (_ snapshot: AccessStatusSnapshot) async -> Void = { _ in },
    ) -> UnlockSurfaceWindowClient {
        UnlockSurfaceWindowClient(
            showWindow: {
                await MainActor.run {
                    if unlockWindowController == nil {
                        let windowClient = UnlockSurfaceWindowClient(
                            showWindow: {},
                            closeWindow: {
                                await MainActor.run {
                                    unlockWindowController?.dismissWithoutTerminate()
                                    unlockWindowController = nil
                                }
                            },
                            openMainWindow: openMainWindow,
                            onUnlocked: onUnlocked,
                        )
                        unlockWindowController = UnlockSurfaceWindowController(windowClient: windowClient)
                    }
                    unlockWindowController?.showWindow(nil)
                    unlockWindowController?.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            },
            closeWindow: {
                await MainActor.run {
                    unlockWindowController?.dismissWithoutTerminate()
                    unlockWindowController = nil
                }
            },
            openMainWindow: openMainWindow,
            onUnlocked: onUnlocked,
        )
    }
}

public extension DependencyValues {
    nonisolated var unlockSurfaceWindowClient: UnlockSurfaceWindowClient {
        get { self[UnlockSurfaceWindowClient.self] }
        set { self[UnlockSurfaceWindowClient.self] = newValue }
    }
}
