import ComposableArchitecture
import CoreServices
import Foundation
import VoyagerShared

public struct EntryFileSystemChange: Equatable, Sendable {
    public var path: String
    public var flags: FSEventStreamEventFlags

    nonisolated public init(path: String, flags: FSEventStreamEventFlags) {
        self.path = path
        self.flags = flags
    }
}

public extension EntryFileSystemChange {
    nonisolated var isStaleWorthyPathChange: Bool {
        flags.entryWatchingContainsAnyFlag([
            kFSEventStreamEventFlagMustScanSubDirs,
            kFSEventStreamEventFlagItemCreated,
            kFSEventStreamEventFlagItemRemoved,
            kFSEventStreamEventFlagItemRenamed,
            kFSEventStreamEventFlagItemModified,
        ])
    }
}

public struct EntryWatchingClient: Sendable {
    public var observeFileSystemChanged: @Sendable () -> AsyncStream<[String]>
    public var startWatchingDirectory: @Sendable (URL) -> AsyncStream<[String]>
    public var startWatchingDirectories: @Sendable ([URL]) -> AsyncStream<[String]>
    public var startWatchingDirectoryChanges: @Sendable ([URL]) -> AsyncStream<[EntryFileSystemChange]>
    public var stopWatchingDirectory: @Sendable () -> Void

    nonisolated public init(
        observeFileSystemChanged: @escaping @Sendable () -> AsyncStream<[String]>,
        startWatchingDirectory: @escaping @Sendable (URL) -> AsyncStream<[String]>,
        startWatchingDirectories: @escaping @Sendable ([URL]) -> AsyncStream<[String]>,
        startWatchingDirectoryChanges: @escaping @Sendable ([URL]) -> AsyncStream<[EntryFileSystemChange]>,
        stopWatchingDirectory: @escaping @Sendable () -> Void,
    ) {
        self.observeFileSystemChanged = observeFileSystemChanged
        self.startWatchingDirectory = startWatchingDirectory
        self.startWatchingDirectories = startWatchingDirectories
        self.startWatchingDirectoryChanges = startWatchingDirectoryChanges
        self.stopWatchingDirectory = stopWatchingDirectory
    }
}

extension EntryWatchingClient: DependencyKey {
    nonisolated public static var liveValue: EntryWatchingClient {
        EntryWatchingClient(
            observeFileSystemChanged: EntryWatchingLive.observeFileSystemChanged,
            startWatchingDirectory: EntryWatchingLive.startWatchingDirectory,
            startWatchingDirectories: EntryWatchingLive.startWatchingDirectories,
            startWatchingDirectoryChanges: EntryWatchingLive.startWatchingDirectoryChanges,
            stopWatchingDirectory: EntryWatchingLive.stopWatchingDirectory,
        )
    }

    nonisolated public static var testValue: EntryWatchingClient {
        EntryWatchingClient(
            observeFileSystemChanged: { AsyncStream { _ in } },
            startWatchingDirectory: { _ in AsyncStream { _ in } },
            startWatchingDirectories: { _ in AsyncStream { _ in } },
            startWatchingDirectoryChanges: { _ in AsyncStream { _ in } },
            stopWatchingDirectory: {},
        )
    }

    nonisolated public static var previewValue: EntryWatchingClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var entryWatchingClient: EntryWatchingClient {
        get { self[EntryWatchingClient.self] }
        set { self[EntryWatchingClient.self] = newValue }
    }
}

public enum EntryWatchingLive {
    final class FSEventsWatcher: @unchecked Sendable {
        nonisolated(unsafe) private var eventStream: FSEventStreamRef?
        private let lock = NSLock()
        nonisolated(unsafe) private var isTerminated = false

        nonisolated init() {}

        nonisolated func setStream(_ stream: FSEventStreamRef?) {
            lock.lock()
            defer { lock.unlock() }
            eventStream = stream
        }

        nonisolated func getStream() -> FSEventStreamRef? {
            lock.lock()
            defer { lock.unlock() }
            return eventStream
        }

        nonisolated func terminate() {
            lock.lock()
            defer { lock.unlock() }
            isTerminated = true
        }

        nonisolated func getIsTerminated() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return isTerminated
        }

        deinit {
            if let stream = eventStream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
        }
    }

    private final class FSEventsContinuationBox: @unchecked Sendable {
        let continuation: AsyncStream<[EntryFileSystemChange]>.Continuation

        nonisolated init(_ continuation: AsyncStream<[EntryFileSystemChange]>.Continuation) {
            self.continuation = continuation
        }
    }

    nonisolated public static let fileSystemChangedNotificationName = NSNotification.Name("VoyagerFileSystemChanged")

    nonisolated static var observeFileSystemChanged: @Sendable () -> AsyncStream<[String]> {
        {
            let notificationCenterClient = NotificationCenterClient.liveValue
            return AsyncStream { continuation in
                final class ObserverBox: @unchecked Sendable {
                    var observer: (any NSObjectProtocol)?
                    let notificationCenterClient: NotificationCenterClient
                    init(notificationCenterClient: NotificationCenterClient) {
                        self.notificationCenterClient = notificationCenterClient
                    }
                }

                let box = ObserverBox(notificationCenterClient: notificationCenterClient)
                box.observer = box.notificationCenterClient.addObserver(
                    fileSystemChangedNotificationName,
                    nil,
                ) { notification in
                    if let paths = notification.userInfo?["paths"] as? [String] {
                        continuation.yield(paths)
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    if let obs = box.observer {
                        box.notificationCenterClient.removeObserver(obs)
                    }
                }
            }
        }
    }

    nonisolated static var startWatchingDirectory: @Sendable (URL) -> AsyncStream<[String]> {
        { url in
            EntryWatchingLive.startWatchingDirectories([url])
        }
    }

    nonisolated static var startWatchingDirectories: @Sendable ([URL]) -> AsyncStream<[String]> {
        { urls in
            AsyncStream { continuation in
                let changes = EntryWatchingLive.startWatchingDirectoryChanges(urls)
                let task = Task {
                    for await batch in changes {
                        continuation.yield(batch.map(\.path))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                }
            }
        }
    }

    nonisolated static var startWatchingDirectoryChanges: @Sendable ([URL]) -> AsyncStream<[EntryFileSystemChange]> {
        { urls in
            AsyncStream { continuation in
                let watchPaths = entryWatchingCanonicalWatchPaths(from: urls)
                guard !watchPaths.isEmpty else {
                    continuation.finish()
                    return
                }

                let watcher = FSEventsWatcher()
                let box = FSEventsContinuationBox(continuation)
                let callback = makeFSEventsCallback()
                var context = makeStreamContext(box: box)

                guard let stream = createStream(paths: watchPaths, callback: callback, context: &context) else {
                    continuation.finish()
                    return
                }

                let queue = DispatchQueue(label: "Voyager.EntryWatchingClient.FSEvents")
                FSEventStreamSetDispatchQueue(stream, queue)

                guard FSEventStreamStart(stream) else {
                    stopStream(stream)
                    continuation.finish()
                    return
                }

                watcher.setStream(stream)

                continuation.onTermination = { @Sendable _ in
                    if let stream = watcher.getStream() {
                        stopStream(stream)
                        watcher.setStream(nil)
                    }
                }
            }
        }
    }

    nonisolated static var stopWatchingDirectory: @Sendable () -> Void {
        {  }
    }

    nonisolated static func entryWatchingCanonicalWatchPaths(from urls: [URL]) -> [String] {
        Array(
            Set(
                urls
                    .map(\.standardizedFileURL.path)
                    .filter { !$0.isEmpty && $0.hasPrefix("/") },
            ),
        )
        .sorted()
    }

    nonisolated private static func makeFSEventsCallback() -> FSEventStreamCallback {
        { _, info, eventCount, eventPaths, eventFlags, _ in
            guard let info else { return }

            let box = Unmanaged<FSEventsContinuationBox>
                .fromOpaque(info)
                .takeUnretainedValue()

            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                return
            }

            let changes = paths.enumerated().map { index, path in
                EntryFileSystemChange(
                    path: path,
                    flags: index < eventCount ? eventFlags[index] : 0,
                )
            }
            box.continuation.yield(changes)
        }
    }

    nonisolated private static func makeStreamContext(
        box: FSEventsContinuationBox,
    ) -> FSEventStreamContext {
        FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(box).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<FSEventsContinuationBox>.fromOpaque(info).release()
            },
            copyDescription: nil,
        )
    }

    nonisolated private static func createStream(
        paths: [String],
        callback: FSEventStreamCallback,
        context: inout FSEventStreamContext,
    ) -> FSEventStreamRef? {
        FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes),
        )
    }

    nonisolated private static func stopStream(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

private extension FSEventStreamEventFlags {
    nonisolated func entryWatchingContainsAnyFlag(_ flags: [Int]) -> Bool {
        flags.contains { flag in
            self & FSEventStreamEventFlags(flag) != 0
        }
    }
}
