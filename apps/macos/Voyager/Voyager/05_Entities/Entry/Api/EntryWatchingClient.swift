import ComposableArchitecture
import CoreServices
import Foundation

public struct EntryWatchingClient: Sendable {
    public var observeFileSystemChanged: @Sendable () -> AsyncStream<[String]>
    public var startWatchingDirectory: @Sendable (URL) -> AsyncStream<[String]>
    public var stopWatchingDirectory: @Sendable () -> Void

    public nonisolated init(
        observeFileSystemChanged: @escaping @Sendable () -> AsyncStream<[String]>,
        startWatchingDirectory: @escaping @Sendable (URL) -> AsyncStream<[String]>,
        stopWatchingDirectory: @escaping @Sendable () -> Void,
    ) {
        self.observeFileSystemChanged = observeFileSystemChanged
        self.startWatchingDirectory = startWatchingDirectory
        self.stopWatchingDirectory = stopWatchingDirectory
    }
}

extension EntryWatchingClient: DependencyKey {
    public nonisolated static var liveValue: EntryWatchingClient {
        EntryWatchingClient(
            observeFileSystemChanged: EntryWatchingLive.observeFileSystemChanged,
            startWatchingDirectory: EntryWatchingLive.startWatchingDirectory,
            stopWatchingDirectory: EntryWatchingLive.stopWatchingDirectory,
        )
    }

    public nonisolated static var testValue: EntryWatchingClient {
        EntryWatchingClient(
            observeFileSystemChanged: { AsyncStream { _ in } },
            startWatchingDirectory: { _ in AsyncStream { _ in } },
            stopWatchingDirectory: {},
        )
    }

    public nonisolated static var previewValue: EntryWatchingClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var entryWatchingClient: EntryWatchingClient {
        get { self[EntryWatchingClient.self] }
        set { self[EntryWatchingClient.self] = newValue }
    }
}
