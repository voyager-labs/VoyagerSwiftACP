import Foundation
import VoyagerEntitiesEntry

actor EntryListHierarchyLoadRecorder {
    struct Request: Equatable {
        let path: String
        let showHidden: Bool
    }

    private var requests: [Request] = []
    private var continuations: [String: CheckedContinuation<[EntryModel], Error>] = [:]
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelledPaths: [String] = []

    func load(url: URL, showHidden: Bool) async throws -> [EntryModel] {
        let path = url.path
        requests.append(.init(path: path, showHidden: showHidden))
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                continuations[path] = continuation
            }
        }, onCancel: {
            Task { await self.cancel(path: path) }
        })
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func recordedRequests() -> [Request] {
        requests
    }

    func succeed(path: String, entries: [EntryModel]) {
        continuations.removeValue(forKey: path)?.resume(returning: entries)
    }

    func fail(path: String) {
        continuations.removeValue(forKey: path)?.resume(throwing: NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
        ))
    }

    func recordedCancelledPaths() -> [String] {
        cancelledPaths
    }

    func waitForCancellationCount(_ count: Int) async {
        while cancelledPaths.count < count {
            await withCheckedContinuation { continuation in
                cancellationWaiters.append(continuation)
            }
        }
    }

    private func cancel(path: String) {
        cancelledPaths.append(path)
        let cancellationWaiters = cancellationWaiters
        self.cancellationWaiters.removeAll()
        cancellationWaiters.forEach { $0.resume() }
        continuations.removeValue(forKey: path)?.resume(throwing: CancellationError())
    }
}
