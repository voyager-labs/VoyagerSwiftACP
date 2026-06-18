import Foundation

/// Thread-safe recorder for file operation calls.
/// Tracks move, copy, trash, delete, and rename operations with source/destination tuples.
final class FileOpsRecorder: @unchecked Sendable {
    private let lock = NSLock()

    private var _movedPaths: [(source: URL, destination: URL)] = []
    private var _copiedPaths: [(source: URL, destination: URL)] = []
    private var _trashedPaths: [URL] = []
    private var _deletedPaths: [URL] = []
    private var _renamedPaths: [(source: URL, destination: URL)] = []

    // MARK: - Move

    func recordMove(source: URL, destination: URL) {
        lock.lock()
        defer { lock.unlock() }
        _movedPaths.append((source, destination))
    }

    var movedPaths: [(source: URL, destination: URL)] {
        lock.lock()
        defer { lock.unlock() }
        return _movedPaths
    }

    // MARK: - Copy

    func recordCopy(source: URL, destination: URL) {
        lock.lock()
        defer { lock.unlock() }
        _copiedPaths.append((source, destination))
    }

    var copiedPaths: [(source: URL, destination: URL)] {
        lock.lock()
        defer { lock.unlock() }
        return _copiedPaths
    }

    // MARK: - Trash

    func recordTrash(path: URL) {
        lock.lock()
        defer { lock.unlock() }
        _trashedPaths.append(path)
    }

    var trashedPaths: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _trashedPaths
    }

    // MARK: - Delete

    func recordDelete(path: URL) {
        lock.lock()
        defer { lock.unlock() }
        _deletedPaths.append(path)
    }

    var deletedPaths: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _deletedPaths
    }

    // MARK: - Rename

    func recordRename(source: URL, destination: URL) {
        lock.lock()
        defer { lock.unlock() }
        _renamedPaths.append((source, destination))
    }

    var renamedPaths: [(source: URL, destination: URL)] {
        lock.lock()
        defer { lock.unlock() }
        return _renamedPaths
    }
}
