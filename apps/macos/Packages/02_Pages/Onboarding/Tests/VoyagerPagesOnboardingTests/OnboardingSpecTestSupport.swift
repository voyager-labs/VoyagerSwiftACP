import Foundation

import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesOnboarding

// MARK: - ONB-001 Shared Fixtures

actor SnapshotRecorder {
    var value: OnboardingProgressSnapshot?

    func set(_ snapshot: OnboardingProgressSnapshot) {
        value = snapshot
    }
}

actor PathRecorder {
    private var paths: [OnboardingOpenMainWindowRequest] = []

    func append(_ request: OnboardingOpenMainWindowRequest) {
        paths.append(request)
    }

    func snapshot() -> [OnboardingOpenMainWindowRequest] {
        paths
    }
}

// MARK: - ONB-003 Shared Fixtures

let kGrantedHelperAccess = FolderAccessResult(
    desktop: .granted,
    documents: .granted,
    downloads: .granted,
)
