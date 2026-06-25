import ComposableArchitecture
import Foundation

public struct FileManagerHomeAiChatClient: Sendable {
    public var createSession: @Sendable () async -> FileManagerHomePickerResult<String>

    public init(
        createSession: @escaping @Sendable () async -> FileManagerHomePickerResult<String>,
    ) {
        self.createSession = createSession
    }
}

extension FileManagerHomeAiChatClient: DependencyKey {
    nonisolated public static var liveValue: FileManagerHomeAiChatClient {
        FileManagerHomeAiChatClient(
            createSession: {
                .selected(UUID().uuidString)
            },
        )
    }

    nonisolated public static var testValue: FileManagerHomeAiChatClient {
        FileManagerHomeAiChatClient(
            createSession: { .cancelled },
        )
    }
}

public extension DependencyValues {
    var homeAiChatClient: FileManagerHomeAiChatClient {
        get { self[FileManagerHomeAiChatClient.self] }
        set { self[FileManagerHomeAiChatClient.self] = newValue }
    }
}
