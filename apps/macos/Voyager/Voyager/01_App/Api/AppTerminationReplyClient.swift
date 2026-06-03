import AppKit
import ComposableArchitecture

struct AppTerminationReplyClient {
    var reply: @Sendable (_ shouldTerminate: Bool) async -> Void
}

extension AppTerminationReplyClient: DependencyKey {
    nonisolated static var liveValue: AppTerminationReplyClient {
        .init(reply: { shouldTerminate in
            await MainActor.run {
                NSApplication.shared.reply(toApplicationShouldTerminate: shouldTerminate)
            }
        })
    }

    nonisolated static var testValue: AppTerminationReplyClient {
        .init(reply: { _ in
            fatalError("appTerminationReplyClient.reply test dependency is not configured")
        })
    }

    nonisolated static var previewValue: AppTerminationReplyClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var appTerminationReplyClient: AppTerminationReplyClient {
        get { self[AppTerminationReplyClient.self] }
        set { self[AppTerminationReplyClient.self] = newValue }
    }
}
