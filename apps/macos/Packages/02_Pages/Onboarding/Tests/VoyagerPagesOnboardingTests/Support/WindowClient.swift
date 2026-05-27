@testable import VoyagerPagesOnboarding

enum WindowClient {
    static var successMock: OnboardingWindowClient {
        OnboardingWindowClient(
            isRequired: { false },
            showIfNeeded: { false },
            showWindow: {},
            closeWindow: {},
            openMainWindow: { _ in true },
        )
    }

    static var failureMock: OnboardingWindowClient {
        OnboardingWindowClient(
            isRequired: { false },
            showIfNeeded: { false },
            showWindow: {},
            closeWindow: {},
            openMainWindow: { _ in false },
        )
    }

    static func recording(pathRecorder: PathRecorder) -> OnboardingWindowClient {
        OnboardingWindowClient(
            isRequired: { false },
            showIfNeeded: { false },
            showWindow: {},
            closeWindow: {},
            openMainWindow: { request in
                await pathRecorder.append(request)
                return true
            },
        )
    }
}
