import Foundation

public struct EntryOperationsCutClearHeuristic: Sendable {
    public var backoffSchedule: [TimeInterval]

    public struct CutSession: Equatable, Sendable {
        public var cutSessionId: String
        public var pasteboard: PasteboardMetadata
        public var sourcePaths: [String]
        public var filePolling: FileExistencePolling
    }

    public struct PasteboardMetadata: Equatable, Sendable {
        public var changeCount: Int
    }

    public struct FileExistencePolling: Equatable, Sendable {
        public var nextCheckAt: Date
        public var nextIntervalIndex: Int
    }

    public enum Decision: Equatable, Sendable {
        case keep(CutSession)
        case clear
    }

    public init(backoffSchedule: [TimeInterval] = Self.defaultBackoffSchedule) {
        self.backoffSchedule = backoffSchedule
    }

    public func makeInitialSession(
        cutSessionId: String,
        pasteboardChangeCount: Int,
        sourcePaths: [String],
        now: Date,
    ) -> CutSession {
        let firstInterval = backoffSchedule.first ?? 0
        return CutSession(
            cutSessionId: cutSessionId,
            pasteboard: .init(changeCount: pasteboardChangeCount),
            sourcePaths: sourcePaths,
            filePolling: .init(nextCheckAt: now.addingTimeInterval(firstInterval), nextIntervalIndex: 0),
        )
    }

    public func evaluate(
        session: CutSession,
        now: Date,
        readPasteboardChangeCount: @Sendable () -> Int,
        readPasteboardCutSessionId: @Sendable () -> String?,
        fileExists: @Sendable (String) -> Bool,
    ) -> Decision {
        var updated = session

        let currentChangeCount = readPasteboardChangeCount()
        if currentChangeCount != session.pasteboard.changeCount {
            let currentSessionId = readPasteboardCutSessionId()
            guard currentSessionId == session.cutSessionId else {
                return .clear
            }
            updated.pasteboard.changeCount = currentChangeCount
        }

        if now >= updated.filePolling.nextCheckAt {
            for path in updated.sourcePaths where !fileExists(path) {
                return .clear
            }

            if !backoffSchedule.isEmpty {
                let nextIndex = min(updated.filePolling.nextIntervalIndex + 1, backoffSchedule.count - 1)
                updated.filePolling.nextIntervalIndex = nextIndex
                updated.filePolling.nextCheckAt = now.addingTimeInterval(backoffSchedule[nextIndex])
            }
        }

        return .keep(updated)
    }

    public static let defaultBackoffSchedule: [TimeInterval] = [0.5, 1, 2, 4, 8, 10]
}
