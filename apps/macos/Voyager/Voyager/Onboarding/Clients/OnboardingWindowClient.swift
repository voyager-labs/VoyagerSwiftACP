import AppKit
import ComposableArchitecture

@MainActor
private var onboardingWindowController: OnboardingWindowController?

struct OnboardingWindowClient: Sendable {
    var showIfNeeded: @Sendable () -> Bool
    var showWindow: @Sendable () async -> Void

    nonisolated init(
        showIfNeeded: @escaping @Sendable () -> Bool,
        showWindow: @escaping @Sendable () async -> Void,
    ) {
        self.showIfNeeded = showIfNeeded
        self.showWindow = showWindow
    }
}

extension OnboardingWindowClient: DependencyKey {
    nonisolated static var liveValue: OnboardingWindowClient {
        let progressStore = OnboardingProgressStore.liveValue
        let showWindow: @Sendable () async -> Void = {
            await MainActor.run {
                if onboardingWindowController == nil {
                    onboardingWindowController = OnboardingWindowController()
                }

                onboardingWindowController?.showWindow(nil)
                onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
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
        )
    }

    nonisolated static var testValue: OnboardingWindowClient {
        OnboardingWindowClient(showIfNeeded: { false }, showWindow: {})
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
