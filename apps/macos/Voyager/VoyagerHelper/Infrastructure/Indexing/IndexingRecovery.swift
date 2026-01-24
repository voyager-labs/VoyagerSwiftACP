import Foundation
import Logging

extension IndexingRequestListener {
    private enum RecoverySkipReason: String {
        case missingReferenceDate = "missing_reference_date"
        case invalidReferenceDate = "invalid_reference_date"
        case timeoutNotReached = "timeout_not_reached"
        case retryLimitReached = "retry_limit_reached"
        case retryIntervalNotReached = "retry_interval_not_reached"
    }

    private enum RecoveryReferenceSource: String {
        case heartbeat
        case startedAt = "started_at"
    }

    private enum RecoveryReference {
        case valid(source: RecoveryReferenceSource, value: String, date: Date)
        case invalid(source: RecoveryReferenceSource, value: String)
        case missing
    }

    private struct RecoveryContext {
        let context: RunningStatusContext
        let now: Date
        let retryCount: Int
        let lastRetryRaw: String?
        let lastRetryAt: Date?
    }

    private struct RecoverySkipLog {
        let reason: RecoverySkipReason
        let context: RunningStatusContext
        let referenceSource: String?
        let referenceValue: String?
        let now: Date
        let elapsedSeconds: TimeInterval?
        let retryCount: Int
        let lastRetryAt: String?
    }

    func recoverIfStuckIfNeeded(context: RunningStatusContext) async -> Bool {
        let now = Date()
        do {
            let recoveryContext = try await makeRecoveryContext(context: context, now: now)
            let reference = try await fetchRecoveryReference()
            return await handleRecoveryReference(reference, context: recoveryContext)
        } catch {
            logger.error("Initial indexing recovery check failed: \(error)")
            return false
        }
    }

    func recordHeartbeatIfNeeded() async {
        let now = Date()
        if let lastHeartbeatAt, now.timeIntervalSince(lastHeartbeatAt) < heartbeatIntervalSeconds {
            return
        }

        do {
            try await upsertStateValue(StateKey.initialIndexingLastHeartbeat, value: iso8601String(from: now))
            lastHeartbeatAt = now
        } catch {
            logger.error("Initial indexing heartbeat update failed: \(error)")
        }
    }

    private func logRecoverySkip(_ log: RecoverySkipLog) {
        let elapsed = log.elapsedSeconds.map { String(Int($0)) } ?? "n/a"
        let lastRetry = log.lastRetryAt ?? "n/a"
        let source = log.referenceSource ?? "n/a"
        let reference = log.referenceValue ?? "n/a"

        let message = """
        Initial indexing recovery skipped: reason=\(log.reason.rawValue), \
        context=\(contextLabel(log.context)), \
        status=\(InitialIndexingStatus.running.rawValue), \
        reference_source=\(source), \
        reference_value=\(reference), \
        now=\(iso8601String(from: log.now)), \
        elapsed_seconds=\(elapsed), \
        timeout_seconds=\(Int(stuckTimeoutSeconds)), \
        retry_count=\(log.retryCount), \
        max_retry_count=\(maxRetryCount), \
        last_retry_at=\(lastRetry), \
        min_retry_interval_seconds=\(Int(minRetryIntervalSeconds))
        """
        logger.info("\(message)")
    }

    private func recordRecoveryAttempt(now: Date, retryCount: Int) async throws {
        let nowString = iso8601String(from: now)
        try await upsertStateValue(StateKey.initialIndexingRetryCount, value: String(retryCount))
        try await upsertStateValue(StateKey.initialIndexingLastRetryAt, value: nowString)
        try await upsertStateValue(StateKey.initialIndexingResetReason, value: "timeout")
    }

    private func fetchRecoveryReference() async throws -> RecoveryReference {
        if let raw = try await fetchStateValue(StateKey.initialIndexingLastHeartbeat) {
            guard let date = parseIso8601(raw) else {
                return .invalid(source: .heartbeat, value: raw)
            }
            return .valid(source: .heartbeat, value: raw, date: date)
        }

        if let raw = try await fetchStateValue(StateKey.initialIndexingStartedAt) {
            guard let date = parseIso8601(raw) else {
                return .invalid(source: .startedAt, value: raw)
            }
            return .valid(source: .startedAt, value: raw, date: date)
        }

        return .missing
    }

    private func makeRecoveryContext(
        context: RunningStatusContext,
        now: Date,
    ) async throws -> RecoveryContext {
        let retryCount = try await fetchIntValue(StateKey.initialIndexingRetryCount) ?? 0
        let lastRetryRaw = try await fetchStateValue(StateKey.initialIndexingLastRetryAt)
        let lastRetryAt = lastRetryRaw.flatMap(parseIso8601)
        return RecoveryContext(
            context: context,
            now: now,
            retryCount: retryCount,
            lastRetryRaw: lastRetryRaw,
            lastRetryAt: lastRetryAt,
        )
    }

    private func handleRecoveryReference(
        _ reference: RecoveryReference,
        context: RecoveryContext,
    ) async -> Bool {
        switch reference {
        case .missing:
            logRecoverySkip(RecoverySkipLog(
                reason: .missingReferenceDate,
                context: context.context,
                referenceSource: nil,
                referenceValue: nil,
                now: context.now,
                elapsedSeconds: nil,
                retryCount: context.retryCount,
                lastRetryAt: context.lastRetryRaw,
            ))
            return false
        case let .invalid(source, value):
            logRecoverySkip(RecoverySkipLog(
                reason: .invalidReferenceDate,
                context: context.context,
                referenceSource: source.rawValue,
                referenceValue: value,
                now: context.now,
                elapsedSeconds: nil,
                retryCount: context.retryCount,
                lastRetryAt: context.lastRetryRaw,
            ))
            return false
        case let .valid(source, value, date):
            return await handleValidReference(
                source: source,
                value: value,
                date: date,
                context: context,
            )
        }
    }

    private func handleValidReference(
        source: RecoveryReferenceSource,
        value: String,
        date: Date,
        context: RecoveryContext,
    ) async -> Bool {
        let elapsed = context.now.timeIntervalSince(date)
        if elapsed < stuckTimeoutSeconds {
            logRecoverySkip(RecoverySkipLog(
                reason: .timeoutNotReached,
                context: context.context,
                referenceSource: source.rawValue,
                referenceValue: value,
                now: context.now,
                elapsedSeconds: elapsed,
                retryCount: context.retryCount,
                lastRetryAt: context.lastRetryRaw,
            ))
            return false
        }

        if context.retryCount >= maxRetryCount {
            logRecoverySkip(RecoverySkipLog(
                reason: .retryLimitReached,
                context: context.context,
                referenceSource: source.rawValue,
                referenceValue: value,
                now: context.now,
                elapsedSeconds: elapsed,
                retryCount: context.retryCount,
                lastRetryAt: context.lastRetryRaw,
            ))
            return false
        }

        if let lastRetryAt = context.lastRetryAt {
            let sinceRetry = context.now.timeIntervalSince(lastRetryAt)
            if sinceRetry < minRetryIntervalSeconds {
                logRecoverySkip(RecoverySkipLog(
                    reason: .retryIntervalNotReached,
                    context: context.context,
                    referenceSource: source.rawValue,
                    referenceValue: value,
                    now: context.now,
                    elapsedSeconds: elapsed,
                    retryCount: context.retryCount,
                    lastRetryAt: context.lastRetryRaw,
                ))
                return false
            }
        }

        logRecoveryTriggered(source: source, elapsedSeconds: elapsed, context: context)
        if await resetStatusForRecovery() {
            await recordRecoveryAndRestart(context: context)
        }
        return true
    }

    private func logRecoveryTriggered(
        source: RecoveryReferenceSource,
        elapsedSeconds: TimeInterval,
        context: RecoveryContext,
    ) {
        let message = """
        Initial indexing recovery triggered: reason=timeout, \
        context=\(contextLabel(context.context)), \
        status=\(InitialIndexingStatus.running.rawValue), \
        reference_source=\(source.rawValue), \
        elapsed_seconds=\(Int(elapsedSeconds)), \
        retry_count=\(context.retryCount), \
        max_retry_count=\(maxRetryCount)
        """
        logger.warning("\(message)")
    }

    private func resetStatusForRecovery() async -> Bool {
        do {
            try await setStatus(.pending)
            return true
        } catch {
            logger.error("Initial indexing recovery status reset failed: \(error)")
            return false
        }
    }

    private func recordRecoveryAndRestart(context: RecoveryContext) async {
        do {
            try await recordRecoveryAttempt(
                now: context.now,
                retryCount: context.retryCount + 1,
            )
        } catch {
            logger.error("Initial indexing recovery attempt record failed: \(error)")
        }

        do {
            try await startInitialIndexing(trigger: .recovery)
        } catch {
            logger.error("Initial indexing recovery run failed: \(error)")
        }
    }

    private func fetchIntValue(_ key: String) async throws -> Int? {
        guard let raw = try await fetchStateValue(key) else { return nil }
        return Int(raw)
    }

    private func contextLabel(_ context: RunningStatusContext) -> String {
        switch context {
        case .prepare:
            "prepare"
        case .request:
            "request"
        }
    }

    func iso8601Now() -> String {
        iso8601String(from: Date())
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func parseIso8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private var stuckTimeoutSeconds: TimeInterval {
        envTimeInterval("VOYAGER_INITIAL_INDEXING_TIMEOUT_SECONDS", defaultValue: 6 * 60 * 60)
    }

    private var maxRetryCount: Int {
        envInt("VOYAGER_INITIAL_INDEXING_MAX_RETRIES", defaultValue: 3)
    }

    private var minRetryIntervalSeconds: TimeInterval {
        envTimeInterval("VOYAGER_INITIAL_INDEXING_MIN_RETRY_INTERVAL_SECONDS", defaultValue: 10 * 60)
    }

    private var heartbeatIntervalSeconds: TimeInterval {
        envTimeInterval("VOYAGER_INITIAL_INDEXING_HEARTBEAT_INTERVAL_SECONDS", defaultValue: 5 * 60)
    }

    private func envTimeInterval(_ key: String, defaultValue: TimeInterval) -> TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let value = TimeInterval(raw)
        else {
            return defaultValue
        }
        return value
    }

    private func envInt(_ key: String, defaultValue: Int) -> Int {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let value = Int(raw)
        else {
            return defaultValue
        }
        return value
    }
}
