import CoreServices
import Foundation

extension EntryClient {
    final class FSEventsWatcher: @unchecked Sendable {
        private nonisolated(unsafe) var eventStream: FSEventStreamRef?
        private nonisolated(unsafe) let lock = NSLock()

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
    }

    nonisolated static var livePostFileSystemChanged: @Sendable ([String]) -> Void {
        { paths in
            let notificationName = NSNotification.Name("VoyagerFileSystemChanged")
            NotificationCenter.default.post(
                name: notificationName,
                object: nil,
                userInfo: ["paths": paths],
            )
        }
    }

    nonisolated static var liveObserveFileSystemChanged: @Sendable () -> AsyncStream<[String]> {
        {
            AsyncStream { continuation in
                final class ObserverBox: @unchecked Sendable {
                    var observer: (any NSObjectProtocol)?
                    let center = NotificationCenter.default
                }

                let notificationName = NSNotification.Name("VoyagerFileSystemChanged")
                let box = ObserverBox()
                box.observer = box.center.addObserver(
                    forName: notificationName,
                    object: nil,
                    queue: .main,
                ) { notification in
                    if let paths = notification.userInfo?["paths"] as? [String] {
                        continuation.yield(paths)
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    if let obs = box.observer {
                        box.center.removeObserver(obs)
                    }
                }
            }
        }
    }

    nonisolated static func makeStartWatchingDirectory(
        watcher: FSEventsWatcher,
    ) -> @Sendable (URL) -> AsyncStream<[String]> {
        { url in
            AsyncStream { continuation in
                final class ContinuationBox {
                    let continuation: AsyncStream<[String]>.Continuation
                    init(_ continuation: AsyncStream<[String]>.Continuation) {
                        self.continuation = continuation
                    }
                }

                let box = ContinuationBox(continuation)

                let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
                    guard let info else { return }

                    let box = Unmanaged<ContinuationBox>
                        .fromOpaque(info)
                        .takeUnretainedValue()

                    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                        return
                    }
                    box.continuation.yield(paths)
                }

                var context = FSEventStreamContext(
                    version: 0,
                    info: Unmanaged.passRetained(box).toOpaque(),
                    retain: nil,
                    release: { info in
                        guard let info else { return }
                        Unmanaged<ContinuationBox>.fromOpaque(info).release()
                    },
                    copyDescription: nil,
                )

                guard let stream = FSEventStreamCreate(
                    nil,
                    callback,
                    &context,
                    [url.path] as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    0.3, // 300ms 지연 (배터리 효율)
                    UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes),
                ) else {
                    continuation.finish()
                    return
                }

                FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)

                guard FSEventStreamStart(stream) else {
                    FSEventStreamInvalidate(stream)
                    FSEventStreamRelease(stream)
                    continuation.finish()
                    return
                }

                watcher.setStream(stream)

                continuation.onTermination = { @Sendable _ in
                    if let stream = watcher.getStream() {
                        FSEventStreamStop(stream)
                        FSEventStreamInvalidate(stream)
                        FSEventStreamRelease(stream)
                        watcher.setStream(nil)
                    }
                }
            }
        }
    }

    nonisolated static func makeStopWatchingDirectory(watcher: FSEventsWatcher) -> @Sendable () -> Void {
        {
            if let stream = watcher.getStream() {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                watcher.setStream(nil)
            }
        }
    }
}
