import Dependencies
@testable import VoyagerPagesOnboarding

enum ProgressClient {
    static var noOp: OnboardingProgressClient {
        OnboardingProgressClient(
            load: { .empty },
            save: { _ in },
            reset: {},
        )
    }

    static var resetRequired: OnboardingProgressClient {
        OnboardingProgressClient(
            load: { .resetRequired },
            save: { _ in },
            reset: {},
        )
    }

    static func recording(
        saveRecorder: LockIsolated<OnboardingProgressSnapshot?>,
        eventLog: EventLogSyncBox? = nil,
    ) -> OnboardingProgressClient {
        OnboardingProgressClient(
            load: { .empty },
            save: { snapshot in
                eventLog?.record("save")
                saveRecorder.setValue(snapshot)
            },
            reset: {},
        )
    }

    static func resetRequiredWithRecorders(
        saveRecorder: LockIsolated<OnboardingProgressSnapshot?>,
        resetRecorder: LockIsolated<Bool>,
    ) -> OnboardingProgressClient {
        OnboardingProgressClient(
            load: { .resetRequired },
            save: { snapshot in saveRecorder.setValue(snapshot) },
            reset: { resetRecorder.setValue(true) },
        )
    }

    static func resuming(from snapshot: OnboardingProgressSnapshot) -> OnboardingProgressClient {
        OnboardingProgressClient(
            load: { .success(snapshot) },
            save: { _ in },
            reset: {},
        )
    }

    static func resumingAndRecording(
        snapshot: OnboardingProgressSnapshot,
        saveRecorder: LockIsolated<OnboardingProgressSnapshot?>,
    ) -> OnboardingProgressClient {
        OnboardingProgressClient(
            load: { .success(snapshot) },
            save: { snapshot in saveRecorder.setValue(snapshot) },
            reset: {},
        )
    }
}
