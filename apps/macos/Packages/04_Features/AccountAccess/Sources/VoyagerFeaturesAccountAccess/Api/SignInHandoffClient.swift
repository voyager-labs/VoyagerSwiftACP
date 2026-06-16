import AppKit
import ComposableArchitecture
import Foundation

/// 인증 handoff를 수행하는 dependency.
/// Mock 경로에서는 즉시 callback URL을 반환하고,
/// 실제 live 경로에서는 외부 브라우저를 열고 콜백 대기 상태로 진입한다.
public struct SignInHandoffClient: Sendable {
    public var performHandoff: @Sendable () async -> SignInHandoffResult

    nonisolated public init(performHandoff: @escaping @Sendable () async -> SignInHandoffResult) {
        self.performHandoff = performHandoff
    }
}

extension SignInHandoffClient: DependencyKey {
    nonisolated public static var liveValue: SignInHandoffClient {
        SignInHandoffClient {
            guard let webBaseURL = ProcessInfo.processInfo.environment["PUBLIC_WEB_BASE_URL"],
                  !webBaseURL.isEmpty
            else {
                return .failure
            }

            let state = AppHandoffStateGenerator.generate()
            let context = AppHandoffContext.onboarding

            let builder = AppHandoffURLBuilder(
                webBaseURL: webBaseURL,
                gatewayURL: ProcessInfo.processInfo.environment["PUBLIC_GATEWAY_URL"] ?? "",
            )

            guard let loginURL = builder.buildLoginURL(state: state, context: context) else {
                return .failure
            }

            let pending = PendingAppHandoff(
                state: state,
                context: context,
                createdAt: Date(),
            )
            await AppHandoffStateStore.shared.store(pending)

            await MainActor.run {
                _ = NSWorkspace.shared.open(loginURL)
            }

            return .awaitingCallback(state: state)
        }
    }

    nonisolated public static var testValue: SignInHandoffClient {
        SignInHandoffClient { .failure }
    }

    nonisolated public static var previewValue: SignInHandoffClient {
        SignInHandoffClient { .failure }
    }
}

public extension DependencyValues {
    nonisolated var signInHandoffClient: SignInHandoffClient {
        get { self[SignInHandoffClient.self] }
        set { self[SignInHandoffClient.self] = newValue }
    }
}
