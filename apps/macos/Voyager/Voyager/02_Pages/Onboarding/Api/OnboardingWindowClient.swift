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
            assertionFailure("onboardingWindowClient.openMainWindow 구현이 주입되지 않았습니다.")
            return false
        })
    }

    nonisolated static func makeLive(
        openMainWindow: @escaping @Sendable (_ path: String?) async -> Bool,
    ) -> OnboardingWindowClient {
        let progressStore = OnboardingProgressStore.liveValue
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
                let required: Bool = switch progressStore.load() {
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
        OnboardingWindowClient(showIfNeeded: { false }, showWindow: {}, closeWindow: {}, openMainWindow: { _ in false })
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
