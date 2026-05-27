@testable import VoyagerPagesOnboarding

actor PathRecorder {
    private var paths: [OnboardingOpenMainWindowRequest] = []

    func append(_ request: OnboardingOpenMainWindowRequest) {
        paths.append(request)
    }

    func snapshot() -> [OnboardingOpenMainWindowRequest] {
        paths
    }
}
