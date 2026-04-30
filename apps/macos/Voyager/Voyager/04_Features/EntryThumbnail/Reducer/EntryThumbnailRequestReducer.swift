import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

@Reducer
struct EntryThumbnailRequestReducer {
    typealias State = EntryThumbnailState
    typealias Action = EntryThumbnailAction

    @Dependency(\.thumbnailGeneratorClient)
    private var thumbnailGeneratorClient
    @Dependency(\.entryThumbnailCacheClient)
    private var entryThumbnailCacheClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .requestThumbnails(paths):
                let candidatePaths = dedupe(paths).filter { path in
                    !state.readyPaths.contains(path)
                        && !state.requestsInFlight.contains(path)
                        && !state.failedPaths.contains(path)
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
                    state.readyPaths.formUnion(cachedSet)
                    state.failedPaths.subtract(cachedSet)
                    state.requestsInFlight.subtract(cachedSet)
                    state.renderVersion += 1
                }

                guard !generatedPaths.isEmpty else { return .none }
                state.requestsInFlight.formUnion(generatedPaths)
                return requestThumbnailsEffect(for: generatedPaths)

            case let .thumbnailsReady(paths):
                let pathSet = Set(paths)
                guard !pathSet.isEmpty else { return .none }
                state.readyPaths.formUnion(pathSet)
                state.requestsInFlight.subtract(pathSet)
                state.failedPaths.subtract(pathSet)
                state.renderVersion += 1
                return .none

            case let .thumbnailRequestFailed(paths):
                let pathSet = Set(paths)
                guard !pathSet.isEmpty else { return .none }
                state.failedPaths.formUnion(pathSet)
                state.requestsInFlight.subtract(pathSet)
                state.renderVersion += 1
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
                        await send(.thumbnailsReady(paths: readyBatch))
                        readyBatch.removeAll(keepingCapacity: true)
                    }
                    if failedBatch.count >= batchSize {
                        await send(.thumbnailRequestFailed(paths: failedBatch))
                        failedBatch.removeAll(keepingCapacity: true)
                    }

                    if let nextPath = remainingIterator.next() {
                        enqueue(path: nextPath)
                    }
                }
            }

            if !readyBatch.isEmpty {
                await send(.thumbnailsReady(paths: readyBatch))
            }
            if !failedBatch.isEmpty {
                await send(.thumbnailRequestFailed(paths: failedBatch))
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
