import Foundation

public actor FileOperationQueue {
    public static let shared = FileOperationQueue()

    private var locks: [URL: Task<Void, Never>] = [:]

    public func run<T: Sendable>(
        _ url: URL,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let key = volumeRoot(for: url)
        let previous = locks[key]
        let task = Task<Void, Never> {
            if let previous {
                await previous.value
            }
        }
        locks[key] = task
        defer {
            locks[key] = nil
            task.cancel()
        }
        return try await operation()
    }

    private func volumeRoot(for url: URL) -> URL {
        (try? url.resourceValues(forKeys: [.volumeURLKey]).volume) ?? url.deletingLastPathComponent()
    }
}
