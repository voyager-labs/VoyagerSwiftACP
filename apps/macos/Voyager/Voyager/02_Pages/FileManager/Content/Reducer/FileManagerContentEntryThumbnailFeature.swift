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
                    !state.entryThumbnails.thumbnailRequestsInFlight.contains(path)
                        && entryThumbnailCacheClient.getThumbnail(for: path) == nil
                }

                let pathsToRequest = Array(filtered.prefix(200))
                guard !pathsToRequest.isEmpty else { return .none }

                state.entryThumbnails.thumbnailRequestsInFlight.formUnion(pathsToRequest)
                return requestThumbnailsEffect(for: pathsToRequest)

            case let .thumbnailsUpdated(paths):
                let pathSet = Set(paths)
                guard !pathSet.isEmpty else { return .none }
                state.entryThumbnails.thumbnailRenderVersion &+= 1
                return .none

            case let .thumbnailRequestsCompleted(paths):
                let pathSet = Set(paths)
                state.entryThumbnails.thumbnailRequestsInFlight.subtract(pathSet)
                return .none

            case let .fileSystemChanged(paths):
                entryThumbnailCacheClient.removeThumbnails(for: paths)
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
            var updatedBatch: [String] = []
            updatedBatch.reserveCapacity(batchSize)
            var completedPaths: [String] = []
            completedPaths.reserveCapacity(paths.count)

            func flushIfNeeded() async {
                if updatedBatch.count >= batchSize {
                    await send(.entries(.thumbnailsUpdated(paths: updatedBatch)))
                    updatedBatch.removeAll(keepingCapacity: true)
                }
            }

            await withTaskGroup(of: (String, Bool).self) { group in
                func addTask(for path: String) {
                    group.addTask(priority: .utility) {
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
                    completedPaths.append(path)
                    if didGenerate {
                        updatedBatch.append(path)
                    }
                    await flushIfNeeded()

                    if let nextPath = remainingIterator.next() {
                        addTask(for: nextPath)
                    }
                }
            }

            if !updatedBatch.isEmpty {
                await send(.entries(.thumbnailsUpdated(paths: updatedBatch)))
            }
            if !completedPaths.isEmpty {
                await send(.entries(.thumbnailRequestsCompleted(paths: completedPaths)))
            }
        }
    }
}
