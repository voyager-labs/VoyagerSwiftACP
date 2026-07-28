import ComposableArchitecture
import Foundation

/// App→Web→App 인증 handoff에서 현재 앱이 어떤 타겟인지 식별한다.
/// Bundle.main 식별자로 런타임에 감지하며, app_target query와 callback scheme을 결정한다.
public enum AppHandoffTarget: Sendable, Equatable, DependencyKey {
    case voyager
    case voyagerDev
    case voyagerProdDebug
    case onboardingHost

    nonisolated public static var liveValue: AppHandoffTarget {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        return resolve(bundleId: bundleId)
    }

    nonisolated public static var testValue: AppHandoffTarget {
        .voyager
    }

    nonisolated public static var previewValue: AppHandoffTarget {
        .voyager
    }

    /// docs 계약의 app_target query 값.
    public var rawValue: String {
        switch self {
        case .voyager: "voyager"
        case .voyagerDev: "voyager_dev"
        case .voyagerProdDebug: "voyager_prod_debug"
        case .onboardingHost: "onboarding_host"
        }
    }

    /// 이 타겟이 수신해야 할 콜백 URL scheme.
    public var callbackScheme: String {
        switch self {
        case .voyager: "voyager"
        case .voyagerDev: "voyager-dev"
        case .voyagerProdDebug: "voyager-proddebug"
        case .onboardingHost: "voyager-onboarding-host"
        }
    }

    /// 정확한 bundle identifier로 AppHandoffTarget을 결정한다.
    /// - fm.voyager.Voyager.dev → .voyagerDev
    /// - fm.voyager.Voyager → .voyager
    /// - fm.voyager.Voyager-proddebug → .voyagerProdDebug
    /// - fm.voyager.OnboardingHost → .onboardingHost
    /// - 그 외 → .voyager (fallback)
    public static func resolve(bundleId: String) -> AppHandoffTarget {
        switch bundleId {
        case "fm.voyager.Voyager.dev": .voyagerDev
        case "fm.voyager.Voyager-proddebug": .voyagerProdDebug
        case "fm.voyager.Voyager": .voyager
        case "fm.voyager.OnboardingHost": .onboardingHost
        default: .voyager
        }
    }
}

public extension DependencyValues {
    nonisolated var appHandoffTarget: AppHandoffTarget {
        get { self[AppHandoffTarget.self] }
        set { self[AppHandoffTarget.self] = newValue }
    }
}
