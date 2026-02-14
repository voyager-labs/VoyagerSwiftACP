import AppKit
import ComposableArchitecture

@MainActor private var onboardingWindowController: OnboardingWindowController?

struct OnboardingWindowClient: Sendable {
    var showIfNeeded: @Sendable () -> Bool
    var showWindow: @Sendable () async -> Void
    var closeWindow: @Sendable () async -> Void
    var openMainWindow: @Sendable (_ path: String?) async -> Bool

    nonisolated init(
        showIfNeeded: @escaping @Sendable () -> Bool,
        showWindow: @escaping @Sendable () async -> Void,
        closeWindow: @escaping @Sendable () async -> Void,
        openMainWindow: @escaping @Sendable (_ path: String?) async -> Bool,
    ) {
        self.showIfNeeded = showIfNeeded
        self.showWindow = showWindow
        self.closeWindow = closeWindow
        self.openMainWindow = openMainWindow
    }
}

extension OnboardingWindowClient: DependencyKey {
    nonisolated static var liveValue: OnboardingWindowClient {
        makeLive(openMainWindow: { _ in
            fatalError("onboardingWindowClient.openMainWindow live dependency is not configured")
        })
    }

    nonisolated static func makeLive(
        openMainWindow: @escaping @Sendable (_ path: String?) async -> Bool,
    ) -> OnboardingWindowClient {
        let progressClient = OnboardingProgressClient.liveValue
        let showWindow: @Sendable () async -> Void = {
            await MainActor.run {
                if onboardingWindowController == nil {
                    onboardingWindowController = OnboardingWindowController(openMainWindow: openMainWindow)
                }

                onboardingWindowController?.showWindow(nil)
                onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        let closeWindow: @Sendable () async -> Void = {
            await MainActor.run {
                onboardingWindowController?.dismissWithoutTerminate()
                onboardingWindowController = nil
            }
        }

        return OnboardingWindowClient(
            showIfNeeded: {
                let required: Bool = switch progressClient.load() {
                case let .success(snapshot):
                    !snapshot.stepState.completeComplete
                case .empty, .resetRequired:
                    true
                }

                if required {
                    Task {
                        await showWindow()
                    }
                }
                return required
            },
            showWindow: showWindow,
            closeWindow: closeWindow,
            openMainWindow: openMainWindow,
        )
    }

    nonisolated static var testValue: OnboardingWindowClient {
        OnboardingWindowClient(
            showIfNeeded: {
                fatalError("onboardingWindowClient.showIfNeeded test dependency is not configured")
            },
            showWindow: {
                fatalError("onboardingWindowClient.showWindow test dependency is not configured")
            },
            closeWindow: {
                fatalError("onboardingWindowClient.closeWindow test dependency is not configured")
            },
            openMainWindow: { _ in
                fatalError("onboardingWindowClient.openMainWindow test dependency is not configured")
            },
        )
    }

    nonisolated static var previewValue: OnboardingWindowClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var onboardingWindowClient: OnboardingWindowClient {
        get { self[OnboardingWindowClient.self] }
        set { self[OnboardingWindowClient.self] = newValue }
    }
}
