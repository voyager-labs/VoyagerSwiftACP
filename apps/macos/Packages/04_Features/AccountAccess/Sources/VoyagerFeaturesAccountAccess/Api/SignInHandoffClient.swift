import AppKit
import ComposableArchitecture
import Foundation
import VoyagerShared

/// 인증 handoff를 수행하는 dependency.
/// Mock 경로에서는 즉시 callback URL을 반환하고,
/// 실제 live 경로에서는 외부 브라우저를 열고 콜백 대기 상태로 진입한다.
public struct SignInHandoffClient: Sendable {
    public var performHandoff: @Sendable (_ context: AppHandoffContext) async -> SignInHandoffResult
    public var beginHandoff: @Sendable (
        _ context: AppHandoffContext,
        _ owner: AccountAccessHandoffScope,
    ) async -> SignInHandoffResult
    nonisolated public init(
        performHandoff: @escaping @Sendable (_ context: AppHandoffContext) async -> SignInHandoffResult,
    ) {
        self.performHandoff = performHandoff
        beginHandoff = { context, _ in
            await performHandoff(context)
        }
    }

    nonisolated public init(
        beginHandoff: @escaping @Sendable (
            _ context: AppHandoffContext,
            _ owner: AccountAccessHandoffScope,
        ) async -> SignInHandoffResult,
    ) {
        performHandoff = { context in
            await beginHandoff(context, .onboarding)
        }
        self.beginHandoff = beginHandoff
    }
}

extension SignInHandoffClient: DependencyKey {
    nonisolated public static var liveValue: SignInHandoffClient {
        SignInHandoffClient(
            beginHandoff: { requestedContext, owner in
                @Dependency(\.appHandoffTarget)
                var appTarget

                guard let webBaseURL = EnvironmentLoader.stringValue(forKey: "PUBLIC_WEB_BASE_URL")
                else {
                    return .failure
                }

                let state = AppHandoffStateGenerator.generate()
                let context = requestedContext

                let builder = AppHandoffURLBuilder(
                    webBaseURL: webBaseURL,
                    gatewayURL: EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL") ?? "",
                )

                guard let loginURL = builder.buildLoginURL(state: state, context: context, appTarget: appTarget) else {
                    return .failure
                }

                let pending = PendingAppHandoff(
                    state: state,
                    context: context,
                    owner: owner,
                    createdAt: Date(),
                )
                return await withTaskCancellationHandler(operation: {
                    guard !Task.isCancelled else { return .cancelled }
                    guard await AppHandoffStateStore.shared.begin(pending) else {
                        return .rejected
                    }
                    guard !Task.isCancelled else {
                        await AppHandoffStateStore.shared.clear(expectedState: state, owner: owner)
                        return .cancelled
                    }
                    await MainActor.run {
                        _ = NSWorkspace.shared.open(loginURL)
                    }
                    guard !Task.isCancelled else {
                        await AppHandoffStateStore.shared.clear(expectedState: state, owner: owner)
                        return .cancelled
                    }
                    return .awaitingCallback(state: state)
                }, onCancel: {
                    Task {
                        await AppHandoffStateStore.shared.clear(expectedState: state, owner: owner)
                    }
                })
            },
        )
    }

    nonisolated public static var testValue: SignInHandoffClient {
        SignInHandoffClient { _ in .failure }
    }

    nonisolated public static var previewValue: SignInHandoffClient {
        SignInHandoffClient { _ in .failure }
    }
}

public extension DependencyValues {
    nonisolated var signInHandoffClient: SignInHandoffClient {
        get { self[SignInHandoffClient.self] }
        set { self[SignInHandoffClient.self] = newValue }
    }
}
