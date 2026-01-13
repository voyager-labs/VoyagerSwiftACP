import Foundation

enum OnboardingStep: String, CaseIterable, Codable, Sendable {
    case welcome
    case betaAccess
    case permissions
    case complete

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .betaAccess:
            "Beta Access"
        case .permissions:
            "Permissions"
        case .complete:
            "Start your voyage"
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
