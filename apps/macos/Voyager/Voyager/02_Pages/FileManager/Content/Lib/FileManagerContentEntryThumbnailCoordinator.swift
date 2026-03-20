import AppKit
import ComposableArchitecture
import Foundation

enum FileManagerContentThumbnailCoordinator {
    struct Dependencies: Sendable {
        let thumbnailGeneratorClient: ThumbnailGeneratorClient
        let entryThumbnailCacheClient: EntryThumbnailCacheClient
    }

    static func reduce(
        _ action: EntryOperationsAction,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction>? {
        switch action {
        case let .requestThumbnails(paths):
            let uniquePaths = Array(Set(paths))
            let filtered = uniquePaths.filter { path in
                !state.entryThumbnails.thumbnailsReady.contains(path)
                    && !state.entryThumbnails.thumbnailRequestsInFlight.contains(path)
                    && !state.entryThumbnails.thumbnailRequestsFailed.contains(path)
            }

            let pathsToRequest = Array(filtered.prefix(200))
            guard !pathsToRequest.isEmpty else { return .none }

            state.entryThumbnails.thumbnailRequestsInFlight.formUnion(pathsToRequest)
            return requestThumbnailsEffect(for: pathsToRequest, dependencies: dependencies)

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
            return nil
        }
    }

    private static func requestThumbnailsEffect(
        for paths: [String],
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        .run { send in
            let thumbnailGeneratorClient = dependencies.thumbnailGeneratorClient
            let entryThumbnailCacheClient = dependencies.entryThumbnailCacheClient

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

            await withTaskGroup(of: (String, Bool).self) { group in
                func enqueueTask(for path: String) {
                    group.addTask(priority: .utility) {
                        await makeThumbnailTask(
                            path: path,
                            size: size,
                            scale: scale,
                            thumbnailGeneratorClient: thumbnailGeneratorClient,
                            entryThumbnailCacheClient: entryThumbnailCacheClient,
                        )
                    }
                }

                for _ in 0 ..< maxConcurrentTasks {
                    guard let nextPath = remainingIterator.next() else { break }
                    enqueueTask(for: nextPath)
                }

                while let (path, didGenerate) = await group.next() {
                    if didGenerate {
                        readyBatch.append(path)
                    } else {
                        failedBatch.append(path)
                    }
                    await flushBatchesIfNeeded(
                        send: send,
                        readyBatch: &readyBatch,
                        failedBatch: &failedBatch,
                        batchSize: batchSize,
                    )

                    if let nextPath = remainingIterator.next() {
                        enqueueTask(for: nextPath)
                    }
                }
            }

            await flushRemainingBatches(send: send, readyBatch: readyBatch, failedBatch: failedBatch)
        }
    }

    private static func makeThumbnailTask(
        path: String,
        size: CGSize,
        scale: CGFloat,
        thumbnailGeneratorClient: ThumbnailGeneratorClient,
        entryThumbnailCacheClient: EntryThumbnailCacheClient,
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

    @MainActor
    private static func flushBatchesIfNeeded(
        send: Send<FileManagerContentAction>,
        readyBatch: inout [String],
        failedBatch: inout [String],
        batchSize: Int,
    ) {
        if readyBatch.count >= batchSize {
            send(.entries(.thumbnailsReady(paths: readyBatch)))
            readyBatch.removeAll(keepingCapacity: true)
        }
        if failedBatch.count >= batchSize {
            send(.entries(.thumbnailRequestFailed(paths: failedBatch)))
            failedBatch.removeAll(keepingCapacity: true)
        }
    }

    @MainActor
    private static func flushRemainingBatches(
        send: Send<FileManagerContentAction>,
        readyBatch: [String],
        failedBatch: [String],
    ) {
        if !readyBatch.isEmpty {
            send(.entries(.thumbnailsReady(paths: readyBatch)))
        }
        if !failedBatch.isEmpty {
            send(.entries(.thumbnailRequestFailed(paths: failedBatch)))
        }
    }
}
