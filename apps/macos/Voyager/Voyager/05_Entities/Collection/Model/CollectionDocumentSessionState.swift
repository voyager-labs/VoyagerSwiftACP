import Foundation

enum CollectionSessionPhase: Equatable, Sendable {
    case idle
    case reopening(kind: OpenKind, base: BaseStatus, inflight: InflightStatus)
    case opened(kind: OpenKind, base: BaseStatus, inflight: InflightStatus)
    case refreshFailed(kind: OpenKind)

    enum BaseStatus: Equatable, Sendable {
        case ready
        case stale
    }

    enum InflightStatus: Equatable, Sendable {
        case none
        case refreshingHydratedSnapshot
        case writingBackRefreshedSnapshot
    }

    enum OpenKind: Equatable, Sendable {
        case definition
        case hydratedSnapshot
    }
}

struct CollectionOpenedDocumentState: Equatable, Sendable {
    var url: URL
    var name: String
    var compatibility: CollectionFileCompatibilityMetadata?
}

struct CollectionSessionMetadata: Equatable, Sendable {
    var lastRefreshAt: Date?
    var baseline: CollectionBaseline?
    var reopenContext: CollectionContext?
}

struct CollectionDocumentSessionState: Equatable, Sendable {
    var phase: CollectionSessionPhase = .idle
    var document: CollectionOpenedDocumentState?
    var metadata: CollectionSessionMetadata = .init()

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.phase == rhs.phase
            && lhs.document == rhs.document
            && lhs.metadata == rhs.metadata
    }

    mutating func captureReopenContext(_ context: CollectionContext?) {
        metadata.reopenContext = context
    }

    mutating func prepareForOpeningCollection(at url: URL) {
        phase = .reopening(kind: .definition, base: .ready, inflight: .none)
        metadata.lastRefreshAt = nil
        document?.compatibility = nil
        document = .init(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            compatibility: nil,
        )
        metadata.baseline = nil
    }

    mutating func completeOpen(
        kind: CollectionSessionPhase.OpenKind,
        isStale: Bool,
        compatibility: CollectionFileCompatibilityMetadata?,
    ) {
        phase = .opened(kind: kind, base: isStale ? .stale : .ready, inflight: .none)
        document?.compatibility = compatibility
        if !isStale {
            metadata.reopenContext = nil
        }
    }

    mutating func finishOpeningTransition() {
        phase = phase.finishedOpeningTransition()
    }

    mutating func markInvalidatedLocally() {
        phase = phase.withBaseStatus(.stale)
        metadata.lastRefreshAt = nil
    }

    mutating func beginRefreshingStaleSession() {
        phase = phase.withInflightStatus(.refreshingHydratedSnapshot)
        metadata.lastRefreshAt = nil
    }

    mutating func finishRefreshWithoutWriteBack() {
        phase = phase.withInflightStatus(.none)
        metadata.lastRefreshAt = nil
    }

    mutating func beginWriteBackAfterRefresh() {
        phase = phase.withInflightStatus(.writingBackRefreshedSnapshot)
    }

    mutating func failRefreshOrWriteBack() {
        let kind = phase.openKindForFailureFallback
        phase = .refreshFailed(kind: kind)
        metadata.lastRefreshAt = nil
    }

    mutating func completeWriteBackSuccess(at currentDate: Date) {
        phase = phase.withInflightStatus(.none)
        phase = phase.withBaseStatus(.ready)
        metadata.lastRefreshAt = currentDate
        metadata.reopenContext = nil
    }
}

extension CollectionSessionPhase {
    var isOpening: Bool {
        if case .reopening = self {
            return true
        }
        return false
    }

    var isStale: Bool {
        switch self {
        case .idle:
            false
        case .refreshFailed:
            true
        case let .reopening(_, base, inflight), let .opened(_, base, inflight):
            base == .stale || inflight != .none
        }
    }

    var openKind: OpenKind? {
        switch self {
        case let .reopening(kind, _, _), let .opened(kind, _, _), let .refreshFailed(kind):
            kind
        case .idle:
            nil
        }
    }

    var inflightStatus: InflightStatus? {
        switch self {
        case let .reopening(_, _, inflight), let .opened(_, _, inflight):
            inflight
        case .refreshFailed, .idle:
            nil
        }
    }

    func finishedOpeningTransition() -> Self {
        switch self {
        case let .reopening(kind, base, inflight):
            .opened(kind: kind, base: base, inflight: inflight)
        case .idle, .opened, .refreshFailed:
            self
        }
    }

    func withBaseStatus(_ baseStatus: BaseStatus) -> Self {
        switch self {
        case .idle:
            baseStatus == .stale
                ? .opened(kind: .definition, base: .stale, inflight: .none)
                : self
        case let .refreshFailed(kind):
            if baseStatus == .stale {
                .refreshFailed(kind: kind)
            } else {
                .opened(kind: kind, base: .ready, inflight: .none)
            }
        case let .reopening(kind, _, inflight):
            .reopening(kind: kind, base: baseStatus, inflight: inflight)
        case let .opened(kind, _, inflight):
            .opened(kind: kind, base: baseStatus, inflight: inflight)
        }
    }

    func withInflightStatus(_ inflightStatus: InflightStatus) -> Self {
        switch self {
        case .idle:
            guard inflightStatus != .none else {
                return self
            }
            return .opened(kind: .definition, base: .ready, inflight: inflightStatus)
        case let .refreshFailed(kind):
            return inflightStatus == .none
                ? self
                : .opened(kind: kind, base: .stale, inflight: inflightStatus)
        case let .reopening(kind, base, _):
            return .reopening(kind: kind, base: base, inflight: inflightStatus)
        case let .opened(kind, base, _):
            return .opened(kind: kind, base: base, inflight: inflightStatus)
        }
    }
}

private extension CollectionSessionPhase {
    var openKindForFailureFallback: OpenKind {
        openKind ?? .definition
    }
}
