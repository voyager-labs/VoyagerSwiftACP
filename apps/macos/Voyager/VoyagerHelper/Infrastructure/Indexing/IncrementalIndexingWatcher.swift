@preconcurrency import CoreServices
import Foundation
@preconcurrency import GRDB
import Logging
import os

private let kIncrementalIndexingEventCallback: FSEventStreamCallback = { _, info, count, _, _, ids in
    guard let info else { return }
    let watcher = Unmanaged<IncrementalIndexingWatcher>
        .fromOpaque(info)
        .takeUnretainedValue()

    watcher.handleEvents(
        eventIds: ids,
        count: count
    )
}

final class IncrementalIndexingWatcher {
    static let shared = IncrementalIndexingWatcher()

    private struct Config {
        let debounceInterval: TimeInterval
        let flushInterval: TimeInterval
        let flushEventCount: Int
        let streamLatency: CFTimeInterval
    }

    private let config = Config(
        debounceInterval: 2.0,
        flushInterval: 2.0,
        flushEventCount: 1000,
        streamLatency: 1.0
    )

    private let debounceQueue = DispatchQueue(label: "VoyagerHelper.IncrementalIndexing.Debounce")
    private let eventQueue = DispatchQueue(label: "VoyagerHelper.IncrementalIndexing.Events")
    private var stream: FSEventStreamRef?
    private var streamThread: Thread?
    private var streamRunLoop: CFRunLoop?
    private var lastEventId: FSEventStreamEventId?
    private var pendingCount = 0
    private var lastFlushTime = Date()
    private var debounceTimer: DispatchSourceTimer?
    private var manager: DatabaseManager?
    private var logger: Logging.Logger?
    private let eventLogger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Voyager",
        category: "VoyagerHelper.IncrementalIndexing"
    )

    private init() {}

    func start(manager: DatabaseManager, logger: Logging.Logger) async throws {
        guard stream == nil else { return }

        self.manager = manager
        self.logger = logger
        let watchedPaths = try await loadWatchedPaths(manager: manager)
        let sinceEventId = try await loadLastEventId(manager: manager)
            ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        try await persistWatchedPaths(manager: manager, paths: watchedPaths)
        logger.info("Incremental indexing watching paths: \(watchedPaths), since_event_id=\(sinceEventId)")

        startStreamThread(
            watchedPaths: watchedPaths,
            sinceEventId: sinceEventId
        )
    }

    func stop() {
        debounceTimer?.cancel()
        debounceTimer = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        stopStreamThread()
        manager = nil
        logger = nil
    }

    private func startStreamThread(
        watchedPaths: [String],
        sinceEventId: FSEventStreamEventId
    ) {
        guard streamThread == nil else { return }
        let thread = Thread { [weak self] in
            self?.runStreamLoop(
                watchedPaths: watchedPaths,
                sinceEventId: sinceEventId
            )
        }
        thread.name = "VoyagerHelper.IncrementalIndexing"
        streamThread = thread
        thread.start()
    }

    private func runStreamLoop(
        watchedPaths: [String],
        sinceEventId: FSEventStreamEventId
    ) {
        guard let logger else { return }
        let paths = watchedPaths as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            kIncrementalIndexingEventCallback,
            &context,
            paths,
            sinceEventId,
            config.streamLatency,
            flags
        ) else {
            logger.error("Failed to create FSEventStream")
            return
        }

        self.stream = stream
        guard let runLoop = CFRunLoopGetCurrent() else {
            logger.error("Failed to access CFRunLoop")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return
        }
        streamRunLoop = runLoop
        FSEventStreamScheduleWithRunLoop(stream, runLoop, CFRunLoopMode.defaultMode.rawValue)
        if !FSEventStreamStart(stream) {
            logger.error("Failed to start FSEventStream")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        } else {
            logger.info("Incremental indexing indexing watcher started")
        }
        CFRunLoopRun()
    }

    private func stopStreamThread() {
        guard let runLoop = streamRunLoop else {
            streamThread = nil
            return
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
        streamRunLoop = nil
        streamThread = nil
    }

    fileprivate func handleEvents(
        eventIds: UnsafePointer<FSEventStreamEventId>,
        count: Int
    ) {
        var maxEventId = lastEventId ?? 0
        for index in 0..<count {
            maxEventId = max(maxEventId, eventIds[index])
        }
        eventQueue.async { [weak self] in
            self?.processEvents(
                count: count,
                maxEventId: maxEventId
            )
        }
    }

    private func processEvents(
        count: Int,
        maxEventId: FSEventStreamEventId
    ) {
        lastEventId = maxEventId
        pendingCount += count
        eventLogger.info(
            "Incremental indexing events received: count=\(count, privacy: .public), last_event_id=\(maxEventId, privacy: .public)"
        )
        flushLastEventId()
    }

    private func scheduleFlush() {
        guard pendingCount > 0 else { return }
        guard manager != nil, logger != nil else { return }

        let now = Date()
        if pendingCount >= config.flushEventCount
            || now.timeIntervalSince(lastFlushTime) >= config.flushInterval
        {
            flushLastEventId()
            return
        }

        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: debounceQueue)
        timer.schedule(deadline: .now() + config.debounceInterval)
        timer.setEventHandler { [weak self] in
            self?.flushLastEventId()
        }
        debounceTimer = timer
        timer.resume()
    }

    private func flushLastEventId() {
        debounceTimer?.cancel()
        debounceTimer = nil

        guard let lastEventId else { return }
        guard let manager else { return }
        eventLogger.info(
            "Incremental indexing flush last_fsevent_id: \(lastEventId, privacy: .public), pending=\(self.pendingCount, privacy: .public)"
        )
        pendingCount = 0
        lastFlushTime = Date()

        Task {
            do {
                try await persistLastEventId(manager: manager, eventId: lastEventId)
            } catch {
                eventLogger.error("Failed to persist last_fsevent_id: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func loadWatchedPaths(manager: DatabaseManager) async throws -> [String] {
        let raw: String? = try await manager.read { db in
            guard try db.tableExists("indexing_state") else { return nil }
            return try String.fetchOne(
                db,
                sql: "SELECT value FROM indexing_state WHERE key = ?",
                arguments: ["watched_paths"]
            )
        }

        let decoded = decodePaths(raw)
        if !decoded.isEmpty {
            return decoded
        }
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return [homePath]
    }

    private func decodePaths(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        if let paths = try? JSONDecoder().decode([String].self, from: data) {
            return paths
        }
        return []
    }

    private func loadLastEventId(manager: DatabaseManager) async throws -> FSEventStreamEventId? {
        let raw: String? = try await manager.read { db in
            guard try db.tableExists("indexing_state") else { return nil }
            return try String.fetchOne(
                db,
                sql: "SELECT value FROM indexing_state WHERE key = ?",
                arguments: ["last_fsevent_id"]
            )
        }
        guard let raw, let value = UInt64(raw) else { return nil }
        return value
    }

    private func persistWatchedPaths(manager: DatabaseManager, paths: [String]) async throws {
        let encoded = try JSONEncoder().encode(paths)
        guard let value = String(bytes: encoded, encoding: .utf8) else {
            throw DatabaseManager.DatabaseError.migrationFailed("watched_paths encoding failed")
        }
        try await manager.write { db in
            let sql = """
            INSERT INTO indexing_state (key, value, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """
            try db.execute(sql: sql, arguments: ["watched_paths", value])
        }
    }

    private func persistLastEventId(
        manager: DatabaseManager,
        eventId: FSEventStreamEventId
    ) async throws {
        let value = String(eventId)
        try await manager.write { db in
            let sql = """
            INSERT INTO indexing_state (key, value, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """
            try db.execute(sql: sql, arguments: ["last_fsevent_id", value])
        }
    }
}
