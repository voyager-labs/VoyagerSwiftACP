import AppKit
import ComposableArchitecture

struct AppTerminationReplyClient: Sendable {
    var reply: @Sendable (_ shouldTerminate: Bool) async -> Void

    nonisolated init(reply: @escaping @Sendable (_ shouldTerminate: Bool) async -> Void) {
        self.reply = reply
    }
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
