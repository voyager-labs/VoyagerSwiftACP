@preconcurrency import CoreServices
import Foundation

struct IncrementalIndexingEventPlan {
    let totalCount: Int
    let maxEventId: FSEventStreamEventId
    let changes: [IncrementalIndexingPlannedChange]
    let rescanPaths: [String]
}

enum IncrementalIndexingAction {
    case upsert
    case delete
}

struct IncrementalIndexingPlannedChange {
    let path: String
    var action: IncrementalIndexingAction
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
        var changes: [IncrementalIndexingPlannedChange] = []
        var indexByPath: [String: Int] = [:]
        var rescanPaths: Set<String> = []
        changes.reserveCapacity(eventCount)

        for index in 0..<eventCount {
            maxEventId = max(maxEventId, ids[index])
            guard let normalized = normalizePath(paths[index], watchedPaths: watchedPaths) else { continue }
            if shouldRescan(flags[index]) {
                rescanPaths.insert(normalized)
            }
            guard let action = resolveAction(flags[index]) else { continue }
            if let existingIndex = indexByPath[normalized] {
                changes[existingIndex].action = action
                continue
            }
            indexByPath[normalized] = changes.count
            changes.append(IncrementalIndexingPlannedChange(path: normalized, action: action))
        }

        return IncrementalIndexingEventPlan(
            totalCount: eventCount,
            maxEventId: maxEventId,
            changes: changes,
            rescanPaths: rescanPaths.sorted()
        )
    }

    // 드롭/오버플로 감지
    private func shouldRescan(_ flags: FSEventStreamEventFlags) -> Bool {
        let mustScan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        let userDropped = FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
        let kernelDropped = FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
        let rescanFlags = mustScan | userDropped | kernelDropped
        return flags & rescanFlags != 0
    }

    // 이벤트 플래그에 따른 처리 결정
    private func resolveAction(_ flags: FSEventStreamEventFlags) -> IncrementalIndexingAction? {
        let removedFlag = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)
        if flags & removedFlag != 0 {
            return .delete
        }

        let upsertFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagItemFinderInfoMod)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagItemChangeOwner)

        guard flags & upsertFlags != 0 else { return nil }
        return .upsert
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
