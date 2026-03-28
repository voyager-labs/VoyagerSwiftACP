import CoreServices
import Foundation

final class HelperExternalFileSystemWatcher {
    private let queue: DispatchQueue
    private let watchRootsProvider: () -> [URL]
    private let onChangedPaths: @MainActor ([String]) async -> Void
    private nonisolated(unsafe) var stream: FSEventStreamRef?

    init(
        queue: DispatchQueue = DispatchQueue(label: "VoyagerHelper.ExternalFileSystemWatcher"),
        watchRootsProvider: @escaping () -> [URL] = { [] },
        onChangedPaths: @escaping @MainActor ([String]) async -> Void,
    ) {
        self.queue = queue
        self.watchRootsProvider = watchRootsProvider
        self.onChangedPaths = onChangedPaths
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    func start() {
        guard stream == nil else { return }

        let paths = watchRootsProvider().map(\.path)
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<HelperExternalFileSystemWatcher>.fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else { return }
                Unmanaged<HelperExternalFileSystemWatcher>.fromOpaque(info).release()
            },
            copyDescription: nil,
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, eventPaths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<HelperExternalFileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                let canonicalPaths = HelperExternalFileChangePayload.canonicalPaths(paths)
                guard !canonicalPaths.isEmpty else { return }
                Task { @MainActor in
                    await watcher.onChangedPaths(canonicalPaths)
                }
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes),
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }

        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
