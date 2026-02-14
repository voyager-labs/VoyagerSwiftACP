import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerContentEntryThumbnailFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.thumbnailGeneratorClient)
    private var thumbnailGeneratorClient
    @Dependency(\.entryThumbnailCacheClient)
    private var entryThumbnailCacheClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .entries(entryAction) = action else {
                return .none
            }

            switch entryAction {
            case let .requestThumbnails(paths):
                let uniquePaths = Array(Set(paths))
                let filtered = uniquePaths.filter { path in
                    !state.entryThumbnails.thumbnailsReady.contains(path)
                        && !state.entryThumbnails.thumbnailRequestsInFlight.contains(path)
                        && !state.entryThumbnails.thumbnailRequestsFailed.contains(path)
                        && !EntryReducerSupport.shouldExcludeThumbnailPath(path)
                }

                let pathsToRequest = Array(filtered.prefix(200))
                guard !pathsToRequest.isEmpty else { return .none }

                state.entryThumbnails.thumbnailRequestsInFlight.formUnion(pathsToRequest)
                return requestThumbnailsEffect(for: pathsToRequest)

            case let .thumbnailsReady(paths):
                let pathSet = Set(paths)
                state.entryThumbnails.thumbnailsReady.formUnion(pathSet)
                state.entryThumbnails.thumbnailRequestsInFlight.subtract(pathSet)
                state.entryThumbnails.thumbnailRequestsFailed.subtract(pathSet)
                return .none

            case let .thumbnailRequestFailed(paths):
                let pathSet = Set(paths)
                state.entryThumbnails.thumbnailRequestsFailed.formUnion(pathSet)
                state.entryThumbnails.thumbnailRequestsInFlight.subtract(pathSet)
                return .none

            default:
                return .none
            }
        }
    }

    private func requestThumbnailsEffect(for paths: [String]) -> Effect<Action> {
        .run { send in
            let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 3.0 }
            let baseSize: CGFloat = 256
            let size = CGSize(width: baseSize, height: baseSize)

            let maxConcurrentTasks = 4
            let batchSize = 10

            var remainingIterator = paths.makeIterator()
            var readyBatch: [String] = []
            readyBatch.reserveCapacity(batchSize)
            var failedBatch: [String] = []
            failedBatch.reserveCapacity(batchSize)

            func flushIfNeeded() async {
                if readyBatch.count >= batchSize {
                    await send(.entries(.thumbnailsReady(paths: readyBatch)))
                    readyBatch.removeAll(keepingCapacity: true)
                }
                if failedBatch.count >= batchSize {
                    await send(.entries(.thumbnailRequestFailed(paths: failedBatch)))
                    failedBatch.removeAll(keepingCapacity: true)
                }
            }

            await withTaskGroup(of: (String, Bool).self) { group in
                func addTask(for path: String) {
                    group.addTask(priority: .utility) {
                        let hasCached = await MainActor.run {
                            entryThumbnailCacheClient.getThumbnail(for: path) != nil
                        }
                        if hasCached {
                            return (path, true)
                        }

                        let url = URL(fileURLWithPath: path)
                        if let thumbnail = await thumbnailGeneratorClient.generateThumbnail(
                            for: url,
                            size: size,
                            scale: scale,
                        ) {
                            await MainActor.run {
                                entryThumbnailCacheClient.saveThumbnail(thumbnail, for: path)
                            }
                            return (path, true)
                        }

                        return (path, false)
                    }
                }

                for _ in 0 ..< maxConcurrentTasks {
                    guard let nextPath = remainingIterator.next() else { break }
                    addTask(for: nextPath)
                }

                while let (path, didGenerate) = await group.next() {
                    if didGenerate {
                        readyBatch.append(path)
                    } else {
                        failedBatch.append(path)
                    }
                    await flushIfNeeded()

                    if let nextPath = remainingIterator.next() {
                        addTask(for: nextPath)
                    }
                }
            }

            if !readyBatch.isEmpty {
                await send(.entries(.thumbnailsReady(paths: readyBatch)))
            }
            if !failedBatch.isEmpty {
                await send(.entries(.thumbnailRequestFailed(paths: failedBatch)))
            }
        }
    }
}
