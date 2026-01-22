@preconcurrency import CoreServices
import Foundation
@preconcurrency import GRDB
import Logging
import os

// FSEvents 콜백 경로/플래그 즉시 복사
private let kIncrementalIndexingEventCallback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
    guard let info, count > 0 else { return }
    let watcher = Unmanaged<IncrementalIndexingWatcher>
        .fromOpaque(info)
        .takeUnretainedValue()

    let pathPointers = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    let pathBuffer = UnsafeBufferPointer(start: pathPointers, count: count)
    var pathList: [String] = []
    pathList.reserveCapacity(count)
    for cPath in pathBuffer {
        pathList.append(String(cString: cPath))
    }

    let flagsList = Array(UnsafeBufferPointer(start: flags, count: count))
    let idsList = Array(UnsafeBufferPointer(start: ids, count: count))

    watcher.handleEvents(
        paths: pathList,
        flags: flagsList,
        ids: idsList
    )
}

final class IncrementalIndexingWatcher {
    static let shared = IncrementalIndexingWatcher()

    private let streamLatency: CFTimeInterval = 1.0

    private let eventQueue = DispatchQueue(label: "VoyagerHelper.IncrementalIndexing.Events", qos: .utility)
    private var stream: FSEventStreamRef?
    private var streamThread: Thread?
    private var streamRunLoop: CFRunLoop?
    private var lastEventId: FSEventStreamEventId?
    private var manager: DatabaseManager?
    private var logger: Logging.Logger?
    private var watchedPaths: [String] = []
    private let homeURL = FileManager.default.homeDirectoryForCurrentUser
    private var cachedVolumeIdentifier: String?
    private var processingTask: Task<Void, Never>?
    private let eventLogger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "Voyager",
                                        category: "VoyagerHelper.IncrementalIndexing")

    // 싱글톤 초기화 제한
    private init() {}

    // 감시 시작 준비
    func start(manager: DatabaseManager, logger: Logging.Logger) async throws {
        guard stream == nil else { return }

        self.manager = manager
        self.logger = logger
        let watchedPaths = try await loadWatchedPaths(manager: manager)
        self.watchedPaths = watchedPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        cachedVolumeIdentifier = InitialIndexingRecordBuilder.volumeIdentifier(from: homeURL)
        let sinceEventId = try await loadLastEventId(manager: manager)
            ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        try await persistWatchedPaths(manager: manager, paths: watchedPaths)
        logger.info("Incremental indexing watching paths: \(watchedPaths), since_event_id=\(sinceEventId)")

        startStreamThread(watchedPaths: watchedPaths, sinceEventId: sinceEventId)
    }

    // 감시 종료 및 상태 정리
    func stop() {
        eventQueue.async { [weak self] in
            guard let self else { return }
            self.processingTask?.cancel()
            self.processingTask = nil
        }
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

    // 스트림 전용 스레드 시작
    private func startStreamThread(watchedPaths: [String], sinceEventId: FSEventStreamEventId) {
        guard streamThread == nil else { return }
        let thread = Thread { [weak self] in
            self?.runStreamLoop(watchedPaths: watchedPaths, sinceEventId: sinceEventId)
        }
        thread.name = "VoyagerHelper.IncrementalIndexing"
        streamThread = thread
        thread.start()
    }

    // 스트림 RunLoop 실행
    private func runStreamLoop(watchedPaths: [String], sinceEventId: FSEventStreamEventId) {
        guard let logger else { return }
        let paths = watchedPaths as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            kIncrementalIndexingEventCallback,
            &context,
            paths,
            sinceEventId,
            streamLatency,
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

    // 스트림 RunLoop 종료
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

    // 이벤트 큐로 전달
    fileprivate func handleEvents(
        paths: [String],
        flags: [FSEventStreamEventFlags],
        ids: [FSEventStreamEventId]
    ) {
        eventQueue.async { [weak self] in
            self?.handleEventsOnQueue(paths: paths, flags: flags, ids: ids)
        }
    }

    // 큐에서 이벤트 정규화 및 집계
    private func handleEventsOnQueue(
        paths: [String],
        flags: [FSEventStreamEventFlags],
        ids: [FSEventStreamEventId]
    ) {
        let eventCount = paths.count
        guard eventCount > 0 else { return }

        var maxEventId = lastEventId ?? 0
        var changes: [(String, FSEventStreamEventFlags)] = []
        changes.reserveCapacity(eventCount)

        for index in 0..<eventCount {
            maxEventId = max(maxEventId, ids[index])
            guard let normalized = normalizePath(paths[index]) else { continue }
            changes.append((normalized, flags[index]))
        }

        lastEventId = maxEventId
        eventLogger.info(
            "Incremental indexing events filtered: total=\(eventCount, privacy: .public), watched=\(changes.count, privacy: .public), last_event_id=\(maxEventId, privacy: .public)"
        )
        enqueueProcessing(changes: changes, maxEventId: maxEventId)
    }

    // DB 반영 작업 직렬화
    private func enqueueProcessing(
        changes: [(String, FSEventStreamEventFlags)],
        maxEventId: FSEventStreamEventId
    ) {
        guard let manager, let logger else { return }
        let cachedIdentifier = cachedVolumeIdentifier
        let homePath = homeURL.standardizedFileURL.path
        let previousTask = processingTask

        processingTask = Task { [weak self] in
            if let previousTask {
                _ = await previousTask.value
            }
            guard let self else { return }
            do {
                if !changes.isEmpty {
                    try await self.applyChanges(
                        changes,
                        manager: manager,
                        logger: logger,
                        cachedVolumeIdentifier: cachedIdentifier,
                        homePath: homePath
                    )
                }
                try await self.persistLastEventId(manager: manager, eventId: maxEventId)
            } catch {
                self.eventLogger.error("Incremental indexing apply failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

extension IncrementalIndexingWatcher {
    // 감시 경로 로드
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

    // 감시 경로 JSON 디코딩
    private func decodePaths(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        if let paths = try? JSONDecoder().decode([String].self, from: data) {
            return paths
        }
        return []
    }

    // 마지막 이벤트 ID 로드
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

    // 감시 경로 저장
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

    // 변경 경로 DB 반영
    private func applyChanges(
        _ changes: [(String, FSEventStreamEventFlags)],
        manager: DatabaseManager,
        logger: Logging.Logger,
        cachedVolumeIdentifier: String?,
        homePath: String
    ) async throws {
        let repo = EntryRepository(manager: manager, logger: logger)
        var insertedOrUpdated = 0
        var deleted = 0
        var lastError: Error?

        for (path, flags) in changes {
            let removed = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0
            let exists = FileManager.default.fileExists(atPath: path)
            if removed || !exists {
                do {
                    deleted += try await repo.deleteByPath(path)
                } catch {
                    lastError = error
                    eventLogger.error("Incremental indexing delete failed: \(String(describing: error), privacy: .public)")
                }
                continue
            }

            guard let mdItem = MDItemCreate(kCFAllocatorDefault, path as CFString) else {
                continue
            }
            let cachedIdentifier = path.hasPrefix(homePath) ? cachedVolumeIdentifier : nil
            let record = await InitialIndexingRecordBuilder.makeRecord(
                mdItem: mdItem,
                path: path,
                homeURL: homeURL,
                cachedVolumeIdentifier: cachedIdentifier
            )
            guard let record else { continue }

            do {
                _ = try await repo.upsertByPath(record)
                insertedOrUpdated += 1
            } catch {
                lastError = error
                eventLogger.error("Incremental indexing upsert failed: \(String(describing: error), privacy: .public)")
            }
        }

        if insertedOrUpdated > 0 || deleted > 0 {
            eventLogger.info(
                "Incremental indexing applied: upserted=\(insertedOrUpdated, privacy: .public), deleted=\(deleted, privacy: .public)"
            )
        }

        if let lastError {
            throw lastError
        }
    }

    // 마지막 이벤트 ID 저장
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

extension IncrementalIndexingWatcher {
    // 감시 경로 기준 표준화
    private func normalizePath(_ path: String) -> String? {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard isWatchedPath(standardized) else { return nil }
        return standardized
    }

    // 감시 경로 하위 여부 판단
    private func isWatchedPath(_ path: String) -> Bool {
        for root in watchedPaths {
            if path == root || path.hasPrefix(root + "/") {
                return true
            }
        }
        return false
    }
}
