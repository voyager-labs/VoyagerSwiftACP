import Foundation

enum OnboardingStep: String, CaseIterable, Codable {
    case welcome
    case betaAccess
    case permissions
    case aiProviderSetup
    case complete

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .betaAccess:
            "Unlock Voyager"
        case .permissions:
            "Permissions"
        case .aiProviderSetup:
            "AI Provider"
        case .complete:
            "Start your voyage"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            "A quick setup before you dive in."
        case .betaAccess:
            "Activate your Voyager license to continue."
        case .permissions:
            "Just a couple of permissions to get you going."
        case .aiProviderSetup:
            "Connect a provider now or set it up later."
        case .complete:
            "All set. You're ready to start."
        }
    }

    var next: OnboardingStep? {
        let nextIndex = index + 1
        guard nextIndex < Self.allCases.count else { return nil }
        return Self.allCases[nextIndex]
    }

    var previous: OnboardingStep? {
        let previousIndex = index - 1
        guard previousIndex >= 0 else { return nil }
        return Self.allCases[previousIndex]
    }
}
