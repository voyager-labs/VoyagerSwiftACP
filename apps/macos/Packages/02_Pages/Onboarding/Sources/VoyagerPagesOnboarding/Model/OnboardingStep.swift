import Foundation

enum OnboardingStep: String, CaseIterable, Codable {
    case welcome
    case accessUnlock
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
        case .accessUnlock:
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
        case .accessUnlock:
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

    /// 커스텀 디코더 — 레거시 `"betaAccess"` rawValue를 `.accessUnlock`로 매핑.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "accessUnlock", "betaAccess":
            self = .accessUnlock
        case "welcome":
            self = .welcome
        case "permissions":
            self = .permissions
        case "aiProviderSetup":
            self = .aiProviderSetup
        case "complete":
            self = .complete
        default:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid OnboardingStep: \(raw)",
                ),
            )
        }
    }
}
