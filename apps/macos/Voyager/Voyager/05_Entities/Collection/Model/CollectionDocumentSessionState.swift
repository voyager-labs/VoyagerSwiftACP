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

struct CollectionDocumentSessionState: Equatable, Sendable {
    enum StaleReason: Equatable, Sendable {
        case invalidatedLocally
        case snapshotHydratedOnOpen
    }

    var phase: CollectionSessionPhase = .idle
    var staleReason: StaleReason?
    var lastRefreshAt: Date?
    var openedCompatibility: CollectionFileCompatibilityMetadata?

    var openedURL: URL?
    var openedName: String?
    var originURL: URL?
    var baseline: CollectionBaseline?
    var reopenContext: CollectionContext?

    var isOpening: Bool {
        get { phase.isOpening }
        set { phase = phase.settingIsOpening(newValue) }
    }

    var isStale: Bool {
        get { phase.isStale }
        set { phase = phase.settingIsStale(newValue) }
    }

    var didHydrateSnapshotOnOpen: Bool {
        get { phase.didHydrateSnapshotOnOpen }
        set { phase = phase.settingDidHydrateSnapshotOnOpen(newValue) }
    }

    var isRefreshingHydratedSnapshot: Bool {
        get { phase.isRefreshingHydratedSnapshot }
        set { phase = phase.settingIsRefreshingHydratedSnapshot(newValue) }
    }

    var isWritingBackRefreshedSnapshot: Bool {
        get { phase.isWritingBackRefreshedSnapshot }
        set { phase = phase.settingIsWritingBackRefreshedSnapshot(newValue) }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.phase == rhs.phase
            && lhs.staleReason == rhs.staleReason
            && lhs.lastRefreshAt == rhs.lastRefreshAt
            && lhs.openedCompatibility == rhs.openedCompatibility
            && lhs.openedURL == rhs.openedURL
            && lhs.openedName == rhs.openedName
            && lhs.originURL == rhs.originURL
            && lhs.baseline == rhs.baseline
            && lhs.reopenContext == rhs.reopenContext
    }

    mutating func captureReopenContext(_ context: CollectionContext?) {
        reopenContext = context
    }

    mutating func prepareForOpeningCollection(at url: URL) {
        phase = .reopening(kind: .definition, base: .ready, inflight: .none)
        staleReason = nil
        lastRefreshAt = nil
        openedCompatibility = nil
        openedName = url.deletingPathExtension().lastPathComponent
        openedURL = url
        originURL = url
        baseline = nil
    }

    mutating func completeOpen(
        kind: CollectionSessionPhase.OpenKind,
        isStale: Bool,
        compatibility: CollectionFileCompatibilityMetadata?,
    ) {
        phase = .opened(kind: kind, base: isStale ? .stale : .ready, inflight: .none)
        openedCompatibility = compatibility
        staleReason = if isStale {
            kind == .hydratedSnapshot ? .snapshotHydratedOnOpen : .invalidatedLocally
        } else {
            nil
        }
        if !isStale {
            reopenContext = nil
        }
    }

    mutating func beginRefreshingStaleSession() {
        phase = phase.settingIsWritingBackRefreshedSnapshot(false)
        phase = phase.settingIsRefreshingHydratedSnapshot(true)
        lastRefreshAt = nil
    }

    mutating func finishRefreshWithoutWriteBack() {
        phase = phase.settingIsRefreshingHydratedSnapshot(false)
        phase = phase.settingIsWritingBackRefreshedSnapshot(false)
        lastRefreshAt = nil
    }

    mutating func beginWriteBackAfterRefresh() {
        phase = phase.settingIsRefreshingHydratedSnapshot(false)
        phase = phase.settingIsWritingBackRefreshedSnapshot(true)
    }

    mutating func failRefreshOrWriteBack() {
        let kind = phase.openKind
        phase = .refreshFailed(kind: kind)
        lastRefreshAt = nil
        if staleReason == nil {
            staleReason = .snapshotHydratedOnOpen
        }
    }

    mutating func completeWriteBackSuccess(at currentDate: Date) {
        phase = phase.settingIsRefreshingHydratedSnapshot(false)
        phase = phase.settingIsWritingBackRefreshedSnapshot(false)
        phase = phase.settingIsStale(false)
        staleReason = nil
        lastRefreshAt = currentDate
        reopenContext = nil
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

    var didHydrateSnapshotOnOpen: Bool {
        switch self {
        case let .reopening(kind, _, _), let .opened(kind, _, _), let .refreshFailed(kind):
            kind == .hydratedSnapshot
        case .idle:
            false
        }
    }

    var isRefreshingHydratedSnapshot: Bool {
        switch self {
        case let .reopening(_, _, inflight), let .opened(_, _, inflight):
            inflight == .refreshingHydratedSnapshot
        case .refreshFailed, .idle:
            false
        }
    }

    var isWritingBackRefreshedSnapshot: Bool {
        switch self {
        case let .reopening(_, _, inflight), let .opened(_, _, inflight):
            inflight == .writingBackRefreshedSnapshot
        case .refreshFailed, .idle:
            false
        }
    }

    func settingIsOpening(_ isOpening: Bool) -> Self {
        if isOpening {
            switch self {
            case .idle:
                return .reopening(kind: .definition, base: .ready, inflight: .none)
            case let .refreshFailed(kind):
                return .reopening(kind: kind, base: .stale, inflight: .none)
            case let .reopening(kind, base, inflight), let .opened(kind, base, inflight):
                return .reopening(kind: kind, base: base, inflight: inflight)
            }
        }

        switch self {
        case let .reopening(kind, base, inflight):
            return .opened(kind: kind, base: base, inflight: inflight)
        case .idle, .opened, .refreshFailed:
            return self
        }
    }

    func settingIsStale(_ isStale: Bool) -> Self {
        switch self {
        case .idle:
            guard isStale else {
                return self
            }
            return .opened(kind: .definition, base: .stale, inflight: .none)
        case let .refreshFailed(kind):
            return isStale ? .refreshFailed(kind: kind) : .opened(kind: kind, base: .ready, inflight: .none)
        case let .reopening(kind, _, inflight):
            return .reopening(kind: kind, base: isStale ? .stale : .ready, inflight: inflight)
        case let .opened(kind, _, inflight):
            return .opened(kind: kind, base: isStale ? .stale : .ready, inflight: inflight)
        }
    }

    func settingDidHydrateSnapshotOnOpen(_ didHydrateSnapshotOnOpen: Bool) -> Self {
        switch self {
        case .idle:
            guard didHydrateSnapshotOnOpen else {
                return self
            }
            return .opened(kind: .hydratedSnapshot, base: .ready, inflight: .none)
        case .refreshFailed:
            return .refreshFailed(kind: didHydrateSnapshotOnOpen ? .hydratedSnapshot : .definition)
        case let .reopening(_, base, inflight):
            return .reopening(
                kind: didHydrateSnapshotOnOpen ? .hydratedSnapshot : .definition,
                base: base,
                inflight: inflight,
            )
        case let .opened(_, base, inflight):
            return .opened(
                kind: didHydrateSnapshotOnOpen ? .hydratedSnapshot : .definition,
                base: base,
                inflight: inflight,
            )
        }
    }

    func settingIsRefreshingHydratedSnapshot(_ isRefreshingHydratedSnapshot: Bool) -> Self {
        switch self {
        case .idle:
            guard isRefreshingHydratedSnapshot else {
                return self
            }
            return .opened(kind: .definition, base: .ready, inflight: .refreshingHydratedSnapshot)
        case let .refreshFailed(kind):
            return isRefreshingHydratedSnapshot ? .opened(
                kind: kind,
                base: .stale,
                inflight: .refreshingHydratedSnapshot,
            ) : self
        case let .reopening(kind, base, inflight):
            return .reopening(
                kind: kind,
                base: base,
                inflight: inflight.settingIsRefreshingHydratedSnapshot(isRefreshingHydratedSnapshot),
            )
        case let .opened(kind, base, inflight):
            return .opened(
                kind: kind,
                base: base,
                inflight: inflight.settingIsRefreshingHydratedSnapshot(isRefreshingHydratedSnapshot),
            )
        }
    }

    func settingIsWritingBackRefreshedSnapshot(_ isWritingBackRefreshedSnapshot: Bool) -> Self {
        switch self {
        case .idle:
            guard isWritingBackRefreshedSnapshot else {
                return self
            }
            return .opened(kind: .definition, base: .ready, inflight: .writingBackRefreshedSnapshot)
        case let .refreshFailed(kind):
            return isWritingBackRefreshedSnapshot ? .opened(
                kind: kind,
                base: .stale,
                inflight: .writingBackRefreshedSnapshot,
            ) : self
        case let .reopening(kind, base, inflight):
            return .reopening(
                kind: kind,
                base: base,
                inflight: inflight.settingIsWritingBackRefreshedSnapshot(isWritingBackRefreshedSnapshot),
            )
        case let .opened(kind, base, inflight):
            return .opened(
                kind: kind,
                base: base,
                inflight: inflight.settingIsWritingBackRefreshedSnapshot(isWritingBackRefreshedSnapshot),
            )
        }
    }
}

private extension CollectionSessionPhase {
    var openKind: OpenKind {
        switch self {
        case let .reopening(kind, _, _), let .opened(kind, _, _), let .refreshFailed(kind):
            kind
        case .idle:
            .definition
        }
    }
}

private extension CollectionSessionPhase.InflightStatus {
    func settingIsRefreshingHydratedSnapshot(_ isRefreshingHydratedSnapshot: Bool) -> Self {
        if isRefreshingHydratedSnapshot {
            return .refreshingHydratedSnapshot
        }

        switch self {
        case .refreshingHydratedSnapshot:
            return .none
        case .none:
            return .none
        case .writingBackRefreshedSnapshot:
            return .writingBackRefreshedSnapshot
        }
    }

    func settingIsWritingBackRefreshedSnapshot(_ isWritingBackRefreshedSnapshot: Bool) -> Self {
        if isWritingBackRefreshedSnapshot {
            return .writingBackRefreshedSnapshot
        }

        switch self {
        case .writingBackRefreshedSnapshot:
            return .none
        case .none:
            return .none
        case .refreshingHydratedSnapshot:
            return .refreshingHydratedSnapshot
        }
    }
}
