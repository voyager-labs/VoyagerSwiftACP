import AppKit
import ComposableArchitecture
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private struct SessionLapseGuardObservedState: Equatable {
    let didSignInFail: Bool
    let accountAccessStepState: AccountAccessStepState
    let isSignInInProgress: Bool
    let errorMessage: String?
}

/// ACC-003-guard_session_lapse: 세션 만료 또는 로그아웃 상태에서 현재 window 콘텐츠를
/// 보호하는 blur 오버레이 + 재인증 다이얼로그.
///
/// ## 표시 조건
/// - `didSignInFail == true` (session_expired): "세션이 만료되었습니다" + 로그인 CTA
/// - accountAccessStepState가 `.complete`가 될 때만 guard 해제
/// - pending/blocked/error와 로그인 진행 중 상태는 overlay 유지
///
/// ## Integration (FileManager 윈도우 오버레이)
/// - 각 FileManager 윈도우의 FileManagerWindowSplitCoordinator가 IfLetStore 기반 오버레이로
///   윈도우 전체(sidebar + content + inspector)를 덮도록 마운트한다.
/// - AppLifecycleFeature의 `ifLet(\.sessionLapseGuard)` child scope와 연결된 store를
///   AppRoot에서 스코핑하여 전달한다 (단일 진실 공급원).
/// - `accountSessionDidEnd` notification 수신 → sessionLapseGuard 표시
///   (명시적 로그아웃의 `signOut`과 세션 만료 양쪽이 모두 동일한 notification을 post하므로
///   두 원인은 같은 경로로 guard에 도달한다. 이는 PRESERVED 동작이다.)
/// - ONB window 활성 시 AppLifecycleFeature에서 skip (ACC-003 skip_onboarding_window)
///
/// ## Contract
/// - blur_opacity = semiopaque
/// - dismissible = false (interactiveDismissDisabled)
/// - skip_onboarding_window = true (AppLifecycleFeature에서 처리, 이 view와 무관)
/// - covers_all_windows = true (각 FileManager 윈도우 오버레이로 동일 store에서 렌더)
public struct SessionLapseGuardView: View {
    private let store: StoreOf<AccountAccessFeature>

    static let loginButtonTitle = "Log in"

    public init(store: StoreOf<AccountAccessFeature>) {
        self.store = store
    }

    public var body: some View {
        WithViewStore(
            store,
            observe: { state in
                SessionLapseGuardObservedState(
                    didSignInFail: state.didSignInFail,
                    accountAccessStepState: state.accountAccessStepState,
                    isSignInInProgress: state.isSignInInProgress,
                    errorMessage: state.errorMessage,
                )
            },
            content: { viewStore in
                let didSignInFail = viewStore.didSignInFail
                let accountAccessStepState = viewStore.accountAccessStepState
                let isSignInInProgress = viewStore.isSignInInProgress
                let errorMessage = viewStore.errorMessage

                let shouldShow = Self.shouldShow(
                    accountAccessStepState: accountAccessStepState,
                    isSignInInProgress: isSignInInProgress,
                )

                if shouldShow {
                    ZStack {
                        VisualEffectView(
                            material: .fullScreenUI,
                            blendingMode: .behindWindow,
                        )
                        .edgesIgnoringSafeArea(.all)

                        VStack(spacing: 16) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)

                            Text(Self.dialogTitle(didSignInFail: didSignInFail))
                                .font(.title3)
                                .fontWeight(.semibold)

                            if let error = errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }

                            Button(Self.loginButtonTitle) {
                                viewStore.send(.loginTapped)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isSignInInProgress)

                            if isSignInInProgress {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .padding(32)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            },
        )
    }

    /// 다이얼로그 제목을 auth state에 따라 반환한다.
    /// - session_expired → "세션이 만료되었습니다"
    /// - logged_out → "로그인이 필요합니다"
    static func dialogTitle(didSignInFail: Bool) -> String {
        if didSignInFail {
            return "Session expired. Log in again to continue."
        }
        return "Log in to continue."
    }

    static func shouldShow(
        accountAccessStepState: AccountAccessStepState,
        isSignInInProgress: Bool,
    ) -> Bool {
        isSignInInProgress || accountAccessStepState != .complete
    }
}
