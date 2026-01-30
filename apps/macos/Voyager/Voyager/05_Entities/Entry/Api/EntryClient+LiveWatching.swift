import CoreServices
import Foundation

extension EntryClient {
    private final class FSEventsContinuationBox: @unchecked Sendable {
        let continuation: AsyncStream<[String]>.Continuation

        nonisolated init(_ continuation: AsyncStream<[String]>.Continuation) {
            self.continuation = continuation
        }
    }

    final class FSEventsWatcher: @unchecked Sendable {
        private nonisolated(unsafe) var eventStream: FSEventStreamRef?
        private let lock = NSLock()
        private nonisolated(unsafe) var isTerminated = false

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
            // 스트림이 남아있는 경우에만 정리 (중복 해제 방지)
            if let stream = eventStream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
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
                let box = FSEventsContinuationBox(continuation)
                let callback = makeFSEventsCallback()
                var context = makeStreamContext(box: box)

                guard let stream = createStream(url: url, callback: callback, context: &context) else {
                    continuation.finish()
                    return
                }

                FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)

                guard FSEventStreamStart(stream) else {
                    stopStream(stream)
                    continuation.finish()
                    return
                }

                watcher.setStream(stream)

                continuation.onTermination = { @Sendable _ in
                    // 중복 해제 방지를 위해 먼저 terminate 상태로 설정
                    watcher.terminate()
                    if let stream = watcher.getStream() {
                        stopStream(stream)
                        watcher.setStream(nil)
                    }
                }
            }
        }
    }

    private nonisolated static func makeFSEventsCallback() -> FSEventStreamCallback {
        { _, info, _, eventPaths, _, _ in
            guard let info else { return }

            let box = Unmanaged<FSEventsContinuationBox>
                .fromOpaque(info)
                .takeUnretainedValue()

            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                return
            }
            box.continuation.yield(paths)
        }
    }

    private nonisolated static func makeStreamContext(
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

    private nonisolated static func createStream(
        url: URL,
        callback: FSEventStreamCallback,
        context: inout FSEventStreamContext,
    ) -> FSEventStreamRef? {
        FSEventStreamCreate(
            nil,
            callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // 300ms 지연 (배터리 효율)
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes),
        )
    }

    private nonisolated static func stopStream(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    nonisolated static func makeStopWatchingDirectory(watcher: FSEventsWatcher) -> @Sendable () -> Void {
        {
            // 이미 terminate 상태인 경우 중복 해제 방지
            guard !watcher.getIsTerminated() else { return }

            if let stream = watcher.getStream() {
                watcher.terminate()
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                watcher.setStream(nil)
            }
        }
    }
}
