import ComposableArchitecture
import Foundation

/// Mock sign-in handoff 결과
public enum SignInHandoffResult: Sendable, Equatable {
    case success(callbackURL: URL)
    case failure
    case cancelled
}

/// Mock sign-in handoff를 수행하는 dependency.
/// Mock-first 빌드에서 외부 브라우저 로그인 플로우를 대체한다.
/// Handoff는 지연을 시뮬레이션한 후 reducer가 기존 callback → restoreSession → fetchAccessStatus 경로로
/// 처리할 결과를 반환한다.
public struct SignInHandoffClient: Sendable {
    public var performHandoff: @Sendable () async -> SignInHandoffResult

    public nonisolated init(performHandoff: @escaping @Sendable () async -> SignInHandoffResult) {
        self.performHandoff = performHandoff
    }
}

extension SignInHandoffClient: DependencyKey {
    public nonisolated static var liveValue: SignInHandoffClient {
        // 실제 구현에서는 외부 브라우저 열기 등의 실제 인증 플로우를 수행한다.
        // 현재는 notConfigured 상태이다.
        SignInHandoffClient { .failure }
    }

    public nonisolated static var testValue: SignInHandoffClient {
        SignInHandoffClient { .failure }
    }

    public nonisolated static var previewValue: SignInHandoffClient {
        SignInHandoffClient { .failure }
    }
}

public extension DependencyValues {
    nonisolated var signInHandoffClient: SignInHandoffClient {
        get { self[SignInHandoffClient.self] }
        set { self[SignInHandoffClient.self] = newValue }
    }
}
