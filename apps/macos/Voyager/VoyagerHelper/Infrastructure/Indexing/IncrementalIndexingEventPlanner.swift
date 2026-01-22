@preconcurrency import CoreServices
import Foundation

struct IncrementalIndexingEventPlan {
    let totalCount: Int
    let maxEventId: FSEventStreamEventId
    let changes: [(String, FSEventStreamEventFlags)]
}

final class IncrementalIndexingEventPlanner {
    // 이벤트 변화 계획 생성
    func plan(
        paths: [String],
        flags: [FSEventStreamEventFlags],
        ids: [FSEventStreamEventId],
        lastEventId: FSEventStreamEventId?,
        watchedPaths: [String]
    ) -> IncrementalIndexingEventPlan? {
        let eventCount = min(paths.count, flags.count, ids.count)
        guard eventCount > 0 else { return nil }

        var maxEventId = lastEventId ?? 0
        var changes: [(String, FSEventStreamEventFlags)] = []
        changes.reserveCapacity(eventCount)

        for index in 0..<eventCount {
            maxEventId = max(maxEventId, ids[index])
            guard let normalized = normalizePath(paths[index], watchedPaths: watchedPaths) else { continue }
            changes.append((normalized, flags[index]))
        }

        return IncrementalIndexingEventPlan(
            totalCount: eventCount,
            maxEventId: maxEventId,
            changes: changes
        )
    }

    // 감시 경로 기준 표준화
    private func normalizePath(_ path: String, watchedPaths: [String]) -> String? {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard isWatchedPath(standardized, watchedPaths: watchedPaths) else { return nil }
        return standardized
    }

    // 감시 경로 하위 여부 판단
    private func isWatchedPath(_ path: String, watchedPaths: [String]) -> Bool {
        for root in watchedPaths {
            if path == root || path.hasPrefix(root + "/") {
                return true
            }
        }
        return false
    }
}
