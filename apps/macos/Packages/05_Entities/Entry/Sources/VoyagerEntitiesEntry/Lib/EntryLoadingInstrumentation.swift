import Foundation
import os

enum EntryLoadingSourceKind: String {
    case directory
    case paths
    case recent
    case tag
    case direct
}

final class EntryLoadingInstrumentation: @unchecked Sendable {
    typealias Begin = @Sendable (Interval, Context) -> Void
    typealias End = @Sendable (Interval, Context, WorkCounts) -> Void

    enum Interval: String, CaseIterable {
        case request = "entry_loading_request"
        case firstCoreBatch = "entry_loading_first_core_batch"
        case coreComplete = "entry_loading_core_complete"
        case metadataComplete = "entry_loading_metadata_complete"

        var signpostName: StaticString {
            switch self {
            case .request: "entry_loading_request"
            case .firstCoreBatch: "entry_loading_first_core_batch"
            case .coreComplete: "entry_loading_core_complete"
            case .metadataComplete: "entry_loading_metadata_complete"
            }
        }
    }

    struct Context {
        let sourceKind: EntryLoadingSourceKind
        let correlationID: UUID
        let inputCount: Int
        let priority: String
    }

    struct WorkCounts: Equatable {
        var validEntries = 0
        var batchCount = 0
        var folderCountProbes = 0
    }

    private let onBegin: Begin
    private let onEnd: End

    init(onBegin: @escaping Begin, onEnd: @escaping End) {
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    static func live() -> EntryLoadingInstrumentation {
        let sink = EntryLoadingSignpostSink()
        return EntryLoadingInstrumentation(onBegin: sink.begin, onEnd: sink.end)
    }

    func begin(_ interval: Interval, context: Context) {
        onBegin(interval, context)
    }

    func end(_ interval: Interval, context: Context, workCounts: WorkCounts) {
        onEnd(interval, context, workCounts)
    }
}

private final class EntryLoadingSignpostSink: @unchecked Sendable {
    private static let signposter = OSSignposter(subsystem: "com.voyager.app", category: "EntryLoading")

    private let lock = NSLock()
    private var states: [EntryLoadingInstrumentation.Interval: OSSignpostIntervalState] = [:]

    func begin(_ interval: EntryLoadingInstrumentation.Interval, _ context: EntryLoadingInstrumentation.Context) {
        let state = Self.signposter.beginInterval(
            interval.signpostName,
            id: Self.signposter.makeSignpostID(),
            """
            source=\(context.sourceKind.rawValue, privacy: .public) correlation=\(
                context.correlationID.uuidString,
                privacy: .public,
            )
            input=\(context.inputCount, privacy: .public) priority=\(context.priority, privacy: .public)
            """,
        )
        lock.withLock {
            states[interval] = state
        }
    }

    func end(
        _ interval: EntryLoadingInstrumentation.Interval,
        _ context: EntryLoadingInstrumentation.Context,
        _ workCounts: EntryLoadingInstrumentation.WorkCounts,
    ) {
        let state = lock.withLock {
            states.removeValue(forKey: interval)
        }
        guard let state else { return }
        Self.signposter.endInterval(
            interval.signpostName,
            state,
            """
            source=\(context.sourceKind.rawValue, privacy: .public) correlation=\(
                context.correlationID.uuidString,
                privacy: .public,
            )
            valid=\(workCounts.validEntries, privacy: .public) batches=\(workCounts.batchCount, privacy: .public)
            folder_count_probes=\(workCounts.folderCountProbes, privacy: .public) priority=\(
                context.priority,
                privacy: .public,
            )
            """,
        )
    }
}

extension EntryMetadataPriority {
    var instrumentationValue: String {
        let probeNames = probes.map { probe in
            switch probe {
            case .spotlight: "spotlight"
            case .tags: "tags"
            case .supplementaryMetadata: "supplementary"
            }
        }
        return probeNames.joined(separator: ",")
    }
}
