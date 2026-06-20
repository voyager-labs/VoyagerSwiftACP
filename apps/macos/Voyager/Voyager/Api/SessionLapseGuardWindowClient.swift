import AppKit
import ComposableArchitecture

// MARK: - SessionLapseGuardPanel (stored reference)

/// ACC-003-guard_session_lapse: NSPanel reference stored at file scope so that
/// `showWindow`/`closeWindow` closures share the same panel instance.
@MainActor private var sessionLapseGuardPanel: NSPanel?

// MARK: - SessionLapseGuardWindowClient

/// TCA dependency that manages a borderless NSPanel overlay for the
/// `SessionLapseGuardView`. The view's contentView is wired separately
/// (C2/C3); this client only owns the panel lifecycle.
struct SessionLapseGuardWindowClient {
    var showWindow: @Sendable () async -> Void
    var closeWindow: @Sendable () async -> Void
}

// MARK: - DependencyKey

extension SessionLapseGuardWindowClient: DependencyKey {
    nonisolated static var liveValue: SessionLapseGuardWindowClient {
        .init(
            showWindow: {
                await MainActor.run {
                    if sessionLapseGuardPanel == nil {
                        let panel = NSPanel(
                            contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false,
                        )
                        panel.level = .modalPanel
                        panel.isFloatingPanel = true
                        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                        let frame = NSScreen.main?.frame ?? .zero
                        panel.setFrame(frame, display: true)
                        sessionLapseGuardPanel = panel
                    }
                    sessionLapseGuardPanel?.orderFrontRegardless()
                }
            },
            closeWindow: {
                await MainActor.run {
                    sessionLapseGuardPanel?.orderOut(nil)
                    sessionLapseGuardPanel = nil
                }
            },
        )
    }

    nonisolated static var testValue: SessionLapseGuardWindowClient {
        .init(
            showWindow: {},
            closeWindow: {},
        )
    }

    nonisolated static var previewValue: SessionLapseGuardWindowClient {
        testValue
    }
}

// MARK: - DependencyValues

extension DependencyValues {
    nonisolated var sessionLapseGuardWindowClient: SessionLapseGuardWindowClient {
        get { self[SessionLapseGuardWindowClient.self] }
        set { self[SessionLapseGuardWindowClient.self] = newValue }
    }
}
