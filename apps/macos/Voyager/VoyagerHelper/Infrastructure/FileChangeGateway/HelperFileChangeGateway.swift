import CoreServices
import Foundation
import Logging
import VoyagerShared

@MainActor
final class HelperFileChangeGateway {
    private final class CallbackBox: @unchecked Sendable {
        let emit: @Sendable ([FileChangeGatewayEvent]) -> Void

        nonisolated init(emit: @escaping @Sendable ([FileChangeGatewayEvent]) -> Void) {
            self.emit = emit
        }
    }

    private let logger: Logger
    private let queue = DispatchQueue(label: "VoyagerHelper.FileChangeGateway.FSEvents")
    private var interests: [String: FileChangeWatchInterest] = [:]
    private var interestUpdatedObserver: (any NSObjectProtocol)?
    private var interestRemovedObserver: (any NSObjectProtocol)?
    private var stream: FSEventStreamRef?
    private var activeWatchRoots: [String] = []
    private var pendingEventsByPath: [String: FileChangeGatewayEvent] = [:]
    private var pendingEventFlushTask: Task<Void, Never>?
    private let eventBatchInterval: Duration
    private let maxEventsPerBatch: Int

    init(
        logger: Logger,
        eventBatchInterval: Duration = .milliseconds(750),
        maxEventsPerBatch: Int = FileChangeGatewayLimits.maxEventsPerBatch,
    ) {
        self.logger = logger
        self.eventBatchInterval = eventBatchInterval
        self.maxEventsPerBatch = maxEventsPerBatch
    }

    func start() {
        startObservingInterestUpdates()
        restartStreamIfNeeded()
    }

    func stop() {
        if let interestUpdatedObserver {
            DistributedNotificationCenter.default().removeObserver(interestUpdatedObserver)
            self.interestUpdatedObserver = nil
        }
        if let interestRemovedObserver {
            DistributedNotificationCenter.default().removeObserver(interestRemovedObserver)
            self.interestRemovedObserver = nil
        }
        flushPendingEvents()
        pendingEventFlushTask?.cancel()
        pendingEventFlushTask = nil
        interests.removeAll()
        activeWatchRoots = []
        stopStream()
    }

    private func startObservingInterestUpdates() {
        guard interestUpdatedObserver == nil, interestRemovedObserver == nil else { return }

        interestUpdatedObserver = DistributedNotificationCenter.default().addObserver(
            forName: .voyagerFileChangeGatewayInterestsUpdated,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let self else { return }
            let updatedInterests = FileChangeGatewayPayload.interests(from: notification.userInfo)
            Task { @MainActor in
                self.updateInterests(updatedInterests)
            }
        }

        interestRemovedObserver = DistributedNotificationCenter.default().addObserver(
            forName: .voyagerFileChangeGatewayInterestsRemoved,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let self else { return }
            let ids = FileChangeGatewayPayload.removedInterestIDs(from: notification.userInfo)
            Task { @MainActor in
                self.removeInterests(ids)
            }
        }
    }

    private func updateInterests(_ updatedInterests: [FileChangeWatchInterest]) {
        guard !updatedInterests.isEmpty else { return }
        for interest in updatedInterests {
            interests[interest.id] = interest
        }
        restartStreamIfNeeded()
    }

    private func removeInterests(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            interests.removeValue(forKey: id)
        }
        restartStreamIfNeeded()
    }

    private func restartStreamIfNeeded() {
        let allRoots = helperFileChangeGatewayAllowedWatchRoots(from: Array(interests.values))
        let nextRoots = helperFileChangeGatewayCappedWatchRoots(allRoots)
        guard nextRoots != activeWatchRoots else { return }

        if allRoots.count > nextRoots.count {
            logger.warning(
                "FileChangeGateway root cap reached",
                metadata: [
                    "allowedRoots": "\(allRoots.count)",
                    "activeRoots": "\(nextRoots.count)",
                ],
            )
        }

        stopStream()
        activeWatchRoots = nextRoots

        guard !nextRoots.isEmpty else {
            logger.debug("FileChangeGateway idle: no active watch roots")
            return
        }

        let callbackBox = CallbackBox { [weak self] events in
            Task { @MainActor in
                self?.publish(events)
            }
        }
        var context = Self.makeStreamContext(callbackBox: callbackBox)
        guard let stream = Self.makeStream(paths: nextRoots, context: &context) else {
            logger.error("Failed to create FileChangeGateway FSEvent stream")
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            Self.stop(stream)
            logger.error("Failed to start FileChangeGateway FSEvent stream")
            return
        }

        self.stream = stream
        logger.info("FileChangeGateway started", metadata: ["roots": "\(nextRoots.count)"])
    }

    private func publish(_ events: [FileChangeGatewayEvent]) {
        let filteredEvents = helperFileChangeGatewayRelevantEvents(
            events,
            interests: Array(interests.values),
        )
        enqueue(filteredEvents)
    }

    private func enqueue(_ events: [FileChangeGatewayEvent]) {
        guard !events.isEmpty else { return }

        for event in events {
            let path = FileChangeScopePolicy.normalizedPath(event.path)
            if let existingEvent = pendingEventsByPath[path] {
                pendingEventsByPath[path] = FileChangeGatewayEvent(
                    path: path,
                    flags: existingEvent.flags | event.flags,
                    emittedAt: max(existingEvent.emittedAt, event.emittedAt),
                )
            } else {
                pendingEventsByPath[path] = event
            }
        }

        guard pendingEventFlushTask == nil else { return }
        let interval = eventBatchInterval
        pendingEventFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            await MainActor.run {
                self?.flushPendingEvents()
            }
        }
    }

    private func flushPendingEvents() {
        pendingEventFlushTask?.cancel()
        pendingEventFlushTask = nil

        let pendingEvents = Array(pendingEventsByPath.values)
        pendingEventsByPath.removeAll()
        guard !pendingEvents.isEmpty else { return }

        let events = helperFileChangeGatewayCompactedEvents(
            pendingEvents,
            interests: Array(interests.values),
            maxEvents: maxEventsPerBatch,
        )
        guard !events.isEmpty else { return }

        DistributedNotificationCenter.default().post(
            name: .voyagerFileChangeGatewayEvents,
            object: nil,
            userInfo: FileChangeGatewayPayload.userInfo(forEvents: events),
        )
    }

    private func stopStream() {
        guard let stream else { return }
        Self.stop(stream)
        self.stream = nil
    }

    nonisolated private static func makeStream(
        paths: [String],
        context: inout FSEventStreamContext,
    ) -> FSEventStreamRef? {
        FSEventStreamCreate(
            nil,
            makeCallback(),
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes),
        )
    }

    nonisolated private static func makeCallback() -> FSEventStreamCallback {
        { _, info, eventCount, eventPaths, eventFlags, _ in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            let events = paths.enumerated().map { index, path in
                FileChangeGatewayEvent(
                    path: path,
                    flags: index < eventCount ? UInt32(eventFlags[index]) : UInt32(0),
                )
            }
            box.emit(events)
        }
    }

    nonisolated private static func makeStreamContext(callbackBox: CallbackBox) -> FSEventStreamContext {
        FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(callbackBox).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<CallbackBox>.fromOpaque(info).release()
            },
            copyDescription: nil,
        )
    }

    nonisolated private static func stop(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

nonisolated func helperFileChangeGatewayAllowedWatchRoots(from interests: [FileChangeWatchInterest]) -> [String] {
    FileChangeScopePolicy.allowedWatchRoots(from: interests.flatMap(\.roots))
}

nonisolated func helperFileChangeGatewayCappedWatchRoots(
    _ roots: [String],
    maxRootCount: Int = FileChangeGatewayLimits.maxActiveWatchRoots,
) -> [String] {
    guard maxRootCount > 0 else { return [] }
    return Array(roots.prefix(maxRootCount))
}

nonisolated func helperFileChangeGatewayWatchRoots(from interests: [FileChangeWatchInterest]) -> [String] {
    helperFileChangeGatewayCappedWatchRoots(helperFileChangeGatewayAllowedWatchRoots(from: interests))
}

nonisolated func helperFileChangeGatewayRelevantEvents(
    _ events: [FileChangeGatewayEvent],
    interests: [FileChangeWatchInterest],
) -> [FileChangeGatewayEvent] {
    let relevantPaths = Set(interests.flatMap { interest in
        FileChangeScopePolicy.interestAffectedPaths(events: events, interest: interest)
    })
    guard !relevantPaths.isEmpty else { return [] }
    return events.filter { relevantPaths.contains(FileChangeScopePolicy.normalizedPath($0.path)) }
}

nonisolated func helperFileChangeGatewayCompactedEvents(
    _ events: [FileChangeGatewayEvent],
    interests: [FileChangeWatchInterest],
    maxEvents: Int = FileChangeGatewayLimits.maxEventsPerBatch,
) -> [FileChangeGatewayEvent] {
    let coalescedEvents = helperFileChangeGatewayCoalescedEvents(events)
    guard maxEvents > 0, coalescedEvents.count > maxEvents else {
        return coalescedEvents
    }

    let affectedRoots = helperFileChangeGatewayAffectedRoots(
        by: coalescedEvents,
        interests: interests,
    )
    guard !affectedRoots.isEmpty else {
        return Array(coalescedEvents.prefix(maxEvents))
    }

    let coarseFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs)
    return affectedRoots.map { root in
        FileChangeGatewayEvent(path: root, flags: coarseFlags)
    }
}

nonisolated func helperFileChangeGatewayCoalescedEvents(_ events: [FileChangeGatewayEvent])
    -> [FileChangeGatewayEvent]
{
    let eventsByPath = events.reduce(into: [String: FileChangeGatewayEvent]()) { result, event in
        let path = FileChangeScopePolicy.normalizedPath(event.path)
        if let existingEvent = result[path] {
            result[path] = FileChangeGatewayEvent(
                path: path,
                flags: existingEvent.flags | event.flags,
                emittedAt: max(existingEvent.emittedAt, event.emittedAt),
            )
        } else {
            result[path] = event
        }
    }
    return eventsByPath.values.sorted { $0.path < $1.path }
}

nonisolated func helperFileChangeGatewayAffectedRoots(
    by events: [FileChangeGatewayEvent],
    interests: [FileChangeWatchInterest],
) -> [String] {
    let roots = Set(interests.flatMap { interest in
        let affectedPaths = Set(FileChangeScopePolicy.interestAffectedPaths(events: events, interest: interest))
        return FileChangeScopePolicy.normalizedAbsolutePaths(interest.roots).filter { root in
            affectedPaths.contains { path in
                FileChangeScopePolicy.affects(
                    root: root,
                    path: path,
                    includeSubfolders: interest.includeSubfolders,
                )
            }
        }
    })
    return roots.sorted()
}
