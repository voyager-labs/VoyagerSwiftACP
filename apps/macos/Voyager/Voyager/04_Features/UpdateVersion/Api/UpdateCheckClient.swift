import AppKit
import ComposableArchitecture
import Foundation
@preconcurrency import Sparkle
import VoyagerShared

public struct UpdateCheckClient: Sendable {
    public var startAtLaunch: @Sendable () async -> Void

    public nonisolated init(
        startAtLaunch: @escaping @Sendable () async -> Void,
    ) {
        self.startAtLaunch = startAtLaunch
    }
}

extension UpdateCheckClient: DependencyKey {
    public nonisolated static var liveValue: UpdateCheckClient {
        UpdateCheckClient(startAtLaunch: {})
    }

    public nonisolated static var testValue: UpdateCheckClient {
        UpdateCheckClient(startAtLaunch: {})
    }

    public nonisolated static var previewValue: UpdateCheckClient {
        UpdateCheckClient(startAtLaunch: {})
    }
}

public extension DependencyValues {
    nonisolated var updateCheckClient: UpdateCheckClient {
        get { self[UpdateCheckClient.self] }
        set { self[UpdateCheckClient.self] = newValue }
    }
}

public extension UpdateCheckClient {
    static func live(updater: SPUUpdater) -> UpdateCheckClient {
        let notificationCenterClient = NotificationCenterClient.liveValue
        return UpdateCheckClient(
            startAtLaunch: {
                let notifications = notificationCenterClient.notifications(
                    NSWindow.didBecomeMainNotification,
                    nil,
                )
                let isReady = await MainActor.run { NSApp.keyWindow != nil }
                if isReady {
                    await MainActor.run {
                        updater.checkForUpdatesInBackground()
                    }
                    return
                }

                for await _ in notifications {
                    await MainActor.run {
                        updater.checkForUpdatesInBackground()
                    }
                    break
                }
            },
        )
    }
}
