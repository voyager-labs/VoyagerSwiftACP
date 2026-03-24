import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct EntryThumbnailOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.thumbnailGeneratorClient)
    private var thumbnailGeneratorClient
    @Dependency(\.entryThumbnailCacheClient)
    private var entryThumbnailCacheClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .thumbnail(.requestThumbnails(paths)):
                let candidatePaths = dedupe(paths).filter { path in
                    !state.thumbnail.readyPaths.contains(path)
                        && !state.thumbnail.requestsInFlight.contains(path)
                        && !state.thumbnail.failedPaths.contains(path)
                }
                let requestedPaths = Array(candidatePaths.prefix(200))
                guard !requestedPaths.isEmpty else { return .none }

                let cachedPaths = requestedPaths.filter { path in
                    MainActor.assumeIsolated {
                        entryThumbnailCacheClient.getThumbnail(for: path) != nil
                    }
                }
                let generatedPaths = requestedPaths.filter { !cachedPaths.contains($0) }

                if !cachedPaths.isEmpty {
                    let cachedSet = Set(cachedPaths)
                    state.thumbnail.readyPaths.formUnion(cachedSet)
                    state.thumbnail.failedPaths.subtract(cachedSet)
                    state.thumbnail.requestsInFlight.subtract(cachedSet)
                    state.thumbnail.renderVersion += 1
                }

                guard !generatedPaths.isEmpty else { return .none }
                state.thumbnail.requestsInFlight.formUnion(generatedPaths)
                return requestThumbnailsEffect(for: generatedPaths)

            case let .thumbnail(.thumbnailsReady(paths)):
                let pathSet = Set(paths)
                guard !pathSet.isEmpty else { return .none }
                state.thumbnail.readyPaths.formUnion(pathSet)
                state.thumbnail.requestsInFlight.subtract(pathSet)
                state.thumbnail.failedPaths.subtract(pathSet)
                state.thumbnail.renderVersion += 1
                return .none

            case let .thumbnail(.thumbnailRequestFailed(paths)):
                let pathSet = Set(paths)
                guard !pathSet.isEmpty else { return .none }
                state.thumbnail.failedPaths.formUnion(pathSet)
                state.thumbnail.requestsInFlight.subtract(pathSet)
                state.thumbnail.renderVersion += 1
                return .none

            default:
                return .none
            }
        }
    }

    private func dedupe(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(paths.count)

        for path in paths where seen.insert(path).inserted {
            result.append(path)
        }

        return result
    }

    private func requestThumbnailsEffect(for paths: [String]) -> Effect<Action> {
        .run { send in
            let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 3.0 }
            let size = CGSize(width: 256, height: 256)
            let maxConcurrentTasks = 4
            let batchSize = 10

            var remainingIterator = paths.makeIterator()
            var readyBatch: [String] = []
            readyBatch.reserveCapacity(batchSize)
            var failedBatch: [String] = []
            failedBatch.reserveCapacity(batchSize)

            await withTaskGroup(of: (String, Bool).self) { group in
                func enqueue(path: String) {
                    group.addTask(priority: .utility) {
                        await makeThumbnailTask(path: path, size: size, scale: scale)
                    }
                }

                for _ in 0 ..< maxConcurrentTasks {
                    guard let nextPath = remainingIterator.next() else { break }
                    enqueue(path: nextPath)
                }

                while let (path, didSucceed) = await group.next() {
                    if didSucceed {
                        readyBatch.append(path)
                    } else {
                        failedBatch.append(path)
                    }

                    if readyBatch.count >= batchSize {
                        await send(.thumbnail(.thumbnailsReady(paths: readyBatch)))
                        readyBatch.removeAll(keepingCapacity: true)
                    }
                    if failedBatch.count >= batchSize {
                        await send(.thumbnail(.thumbnailRequestFailed(paths: failedBatch)))
                        failedBatch.removeAll(keepingCapacity: true)
                    }

                    if let nextPath = remainingIterator.next() {
                        enqueue(path: nextPath)
                    }
                }
            }

            if !readyBatch.isEmpty {
                await send(.thumbnail(.thumbnailsReady(paths: readyBatch)))
            }
            if !failedBatch.isEmpty {
                await send(.thumbnail(.thumbnailRequestFailed(paths: failedBatch)))
            }
        }
    }

    private func makeThumbnailTask(
        path: String,
        size: CGSize,
        scale: CGFloat,
    ) async -> (String, Bool) {
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
