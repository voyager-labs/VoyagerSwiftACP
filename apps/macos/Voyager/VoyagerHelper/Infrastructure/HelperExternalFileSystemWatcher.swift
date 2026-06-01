import CoreServices
import Foundation

final class HelperExternalFileSystemWatcher {
    final class CallbackBox: @unchecked Sendable {
        let emit: @Sendable ([String]) -> Void

        init(emit: @escaping @Sendable ([String]) -> Void) {
            self.emit = emit
        }
    }

    private let queue: DispatchQueue
    private let watchRootsProvider: () -> [URL]
    private let onChangedPaths: @MainActor ([String]) async -> Void
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    nonisolated(unsafe) private var watchRootsObserver: NSObjectProtocol?
    private var watchRoots: [URL] = []
    private let callbackBox: CallbackBox

    init(
        queue: DispatchQueue = DispatchQueue(label: "VoyagerHelper.ExternalFileSystemWatcher"),
        watchRootsProvider: @escaping () -> [URL] = { [] },
        onChangedPaths: @escaping @MainActor ([String]) async -> Void,
    ) {
        self.queue = queue
        self.watchRootsProvider = watchRootsProvider
        self.onChangedPaths = onChangedPaths
        callbackBox = CallbackBox { paths in
            Task { @MainActor in
                await onChangedPaths(paths)
            }
        }
    }

    deinit {
        if let watchRootsObserver {
            DistributedNotificationCenter.default().removeObserver(watchRootsObserver)
        }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    func start() {
        startObservingWatchRoots()
        watchRoots = canonicalWatchRoots(watchRootsProvider())
        restartStreamIfNeeded()
    }

    func updateWatchRoots(_ roots: [URL]) {
        let canonicalRoots = canonicalWatchRoots(roots)
        guard canonicalRoots != watchRoots else { return }
        watchRoots = canonicalRoots
        restartStreamIfNeeded()
    }

    private func startObservingWatchRoots() {
        guard watchRootsObserver == nil else { return }

        watchRootsObserver = DistributedNotificationCenter.default().addObserver(
            forName: .voyagerHelperFSWatchRootsChanged,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let self,
                  let payload = HelperExternalFileChangePayload.from(
                      userInfo: notification.userInfo,
                      allowEmptyPaths: true,
                  )
            else { return }
            let roots = payload.paths.map { URL(fileURLWithPath: $0) }
            Task { @MainActor in
                self.updateWatchRoots(roots)
            }
        }
    }

    private func restartStreamIfNeeded() {
        stop()

        let paths = watchRoots.map(\.path)
        guard !paths.isEmpty else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(callbackBox).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<CallbackBox>.fromOpaque(info).release()
            },
            copyDescription: nil,
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, eventPaths, _, _ in
                guard let info else { return }
                let callbackBox = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                let canonicalPaths = helperFSFilterNoise(from: HelperExternalFileChangePayload.canonicalPaths(paths))
                guard !canonicalPaths.isEmpty else { return }
                callbackBox.emit(canonicalPaths)
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes),
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
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

    private func canonicalWatchRoots(_ roots: [URL]) -> [URL] {
        Array(
            Set(
                roots
                    .map(\.standardizedFileURL)
                    .filter { !$0.path.isEmpty },
            ),
        )
        .sorted(by: { $0.path < $1.path })
    }
}

nonisolated private func helperFSFilterNoise(from paths: [String]) -> [String] {
    paths.filter { !helperFSIsIgnoredEventPath($0) }
}

nonisolated private func helperFSIsIgnoredEventPath(_ path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    let last = url.lastPathComponent
    if last == ".DS_Store" || last == "helper_external_file_changes.json" || last ==
        "helper_external_file_changes.lock" || last == "helper_debug.log"
    {
        return true
    }
    return false
}
