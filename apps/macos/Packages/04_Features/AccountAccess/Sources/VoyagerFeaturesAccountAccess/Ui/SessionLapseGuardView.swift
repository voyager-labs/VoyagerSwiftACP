import AppKit
import ComposableArchitecture
import SwiftUI

// MARK: - Blur Effect View (NSVisualEffectView bridge)

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

// MARK: - Guard observation state

private struct SessionLapseGuardObservedState: Equatable {
    let didSignInFail: Bool
    let hasAccountSession: Bool
    let isSignInInProgress: Bool
    let errorMessage: String?
}

// MARK: - SessionLapseGuardView

/// ACC-003-guard_session_lapse: 세션 만료 또는 로그아웃 상태에서 현재 window 콘텐츠를
/// 보호하는 blur 오버레이 + 재인증 다이얼로그.
///
/// ## 표시 조건
/// - `didSignInFail == true` (session_expired): "세션이 만료되었습니다" + 로그인 CTA
/// - `!hasAccountSession && !isSignInInProgress` (logged_out): "로그인이 필요합니다" + 로그인 CTA
///
/// ## Integration (AppLifecycleFeature)
/// ```swift
/// // AppReducer.swift
/// SessionLapseGuardView(store: store.scope(
///     state: \.accountAccess,
///     action: \.accountAccess
/// ))
/// ```
///
/// ## Contract
/// - blur_opacity = semiopaque
/// - dismissible = false (interactiveDismissDisabled)
/// - skip_onboarding_window = true (별도 처리, 이 view와 무관)
/// - covers_all_windows = true (호출 측에서 각 window에 추가)
public struct SessionLapseGuardView: View {
    private let store: StoreOf<AccountAccessFeature>

    public init(store: StoreOf<AccountAccessFeature>) {
        self.store = store
    }

    public var body: some View {
        WithViewStore(store, observe: { state in
            SessionLapseGuardObservedState(
                didSignInFail: state.didSignInFail,
                hasAccountSession: state.hasAccountSession,
                isSignInInProgress: state.isSignInInProgress,
                errorMessage: state.errorMessage,
            )
        }) { viewStore in
            let didSignInFail = viewStore.didSignInFail
            let hasAccountSession = viewStore.hasAccountSession
            let isSignInInProgress = viewStore.isSignInInProgress
            let errorMessage = viewStore.errorMessage

            let shouldShow = didSignInFail
                || (!hasAccountSession && !isSignInInProgress)

            if shouldShow {
                ZStack {
                    // Semi-opaque blur background (NSVisualEffectView)
                    VisualEffectView(
                        material: .fullScreenUI,
                        blendingMode: .behindWindow,
                    )
                    .edgesIgnoringSafeArea(.all)

                    // Centered reauth dialog
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text(dialogTitle(didSignInFail: didSignInFail))
                            .font(.title3)
                            .fontWeight(.semibold)

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button("로그인") {
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
        }
    }

    /// 다이얼로그 제목을 auth state에 따라 반환한다.
    /// - session_expired → "세션이 만료되었습니다"
    /// - logged_out → "로그인이 필요합니다"
    private func dialogTitle(didSignInFail: Bool) -> String {
        if didSignInFail {
            return "세션이 만료되었습니다"
        }
        return "로그인이 필요합니다"
    }
}
