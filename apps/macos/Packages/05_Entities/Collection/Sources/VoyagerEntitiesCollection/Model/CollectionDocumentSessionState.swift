import Foundation

public enum CollectionSessionPhase: Equatable, Sendable {
    case idle
    case reopening(kind: OpenKind, base: BaseStatus, inflight: InflightStatus)
    case opened(kind: OpenKind, base: BaseStatus, inflight: InflightStatus)
    case refreshFailed(kind: OpenKind)

    public enum BaseStatus: Equatable, Sendable {
        case ready
        case stale
    }

    public enum InflightStatus: Equatable, Sendable {
        case none
        case refreshingHydratedSnapshot
        case writingBackRefreshedSnapshot
    }

    public enum OpenKind: Equatable, Sendable {
        case definition
        case hydratedSnapshot
    }
}

public struct CollectionOpenedDocumentState: Equatable, Sendable {
    public var url: URL
    public var name: String
    public var compatibility: CollectionFileCompatibilityMetadata?

    public init(url: URL, name: String, compatibility: CollectionFileCompatibilityMetadata? = nil) {
        self.url = url
        self.name = name
        self.compatibility = compatibility
    }
}

public struct CollectionSessionMetadata: Equatable, Sendable {
    public var lastRefreshAt: Date?
    public var baseline: CollectionBaseline?
    public var reopenContext: CollectionContext?

    public init(lastRefreshAt: Date? = nil, baseline: CollectionBaseline? = nil, reopenContext: CollectionContext? = nil) {
        self.lastRefreshAt = lastRefreshAt
        self.baseline = baseline
        self.reopenContext = reopenContext
    }
}

public struct CollectionDocumentSessionState: Equatable, Sendable {
    public var phase: CollectionSessionPhase = .idle
    public var document: CollectionOpenedDocumentState?
    public var metadata: CollectionSessionMetadata = .init()
    public var pendingComposerResetOnNavigation: Bool = false

    public init(
        phase: CollectionSessionPhase = .idle,
        document: CollectionOpenedDocumentState? = nil,
        metadata: CollectionSessionMetadata = .init(),
        pendingComposerResetOnNavigation: Bool = false
    ) {
        self.phase = phase
        self.document = document
        self.metadata = metadata
        self.pendingComposerResetOnNavigation = pendingComposerResetOnNavigation
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.phase == rhs.phase
            && lhs.document == rhs.document
            && lhs.metadata == rhs.metadata
            && lhs.pendingComposerResetOnNavigation == rhs.pendingComposerResetOnNavigation
    }

    public mutating func captureReopenContext(_ context: CollectionContext?) {
        metadata.reopenContext = context
    }

    mutating func prepareForOpeningCollection(at url: URL) {
        phase = .reopening(kind: .definition, base: .ready, inflight: .none)
        metadata.lastRefreshAt = nil
        document?.compatibility = nil
        document = .init(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            compatibility: nil
        )
        metadata.baseline = nil
    }

    mutating func completeOpen(
        kind: CollectionSessionPhase.OpenKind,
        isStale: Bool,
        compatibility: CollectionFileCompatibilityMetadata?
    ) {
        phase = .opened(kind: kind, base: isStale ? .stale : .ready, inflight: .none)
        document?.compatibility = compatibility
        if !isStale {
            metadata.reopenContext = nil
        }
    }

    public mutating func finishOpeningTransition() {
        phase = phase.finishedOpeningTransition()
    }

    public mutating func markInvalidatedLocally() {
        phase = phase.withBaseStatus(.stale)
        metadata.lastRefreshAt = nil
    }

    public mutating func beginRefreshingStaleSession() {
        phase = phase.withInflightStatus(.refreshingHydratedSnapshot)
        metadata.lastRefreshAt = nil
    }

    public mutating func finishRefreshWithoutWriteBack() {
        phase = phase.withInflightStatus(.none)
        metadata.lastRefreshAt = nil
    }

    public mutating func beginWriteBackAfterRefresh() {
        phase = phase.withInflightStatus(.writingBackRefreshedSnapshot)
    }

    public mutating func failRefreshOrWriteBack() {
        let kind = phase.openKindForFailureFallback
        phase = .refreshFailed(kind: kind)
        metadata.lastRefreshAt = nil
    }

    public mutating func completeWriteBackSuccess(at currentDate: Date) {
        phase = phase.withInflightStatus(.none)
        phase = phase.withBaseStatus(.ready)
        metadata.lastRefreshAt = currentDate
        metadata.reopenContext = nil
    }
}

public extension CollectionSessionPhase {
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

    var isInflightRefresh: Bool {
        inflightStatus == .refreshingHydratedSnapshot
    }

    var isInflightWriteBack: Bool {
        inflightStatus == .writingBackRefreshedSnapshot
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
