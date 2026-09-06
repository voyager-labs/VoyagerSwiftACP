import ComposableArchitecture

/// reducer가 현재 점유한 effect 단계다. completion은 이 단계가 일치할 때만
/// 수용되고, 그 외의 늦은 completion은 generation fence와 함께 무시된다.
enum EntryPropertiesPhase: CaseIterable, Hashable {
    case idle
    case discovering
    case ready
    case preparing
    case prepared
    case executing
    case applied
    case appliedUnverified
    case terminal
}

@ObservableState
public struct EntryPropertiesState: Equatable, Sendable {
    public internal(set) var selection: EntryPropertiesSelection
    public internal(set) var capabilityReport: EntryPropertiesCapabilityReport?
    public internal(set) var targetSnapshot: EntryPropertiesTargetSnapshot?
    public internal(set) var proposal: EntryPropertiesProposal?
    public internal(set) var canonicalResult: EntryPropertiesCanonicalResult?
    public internal(set) var status: EntryPropertiesStatus
    public internal(set) var lastOutcome: EntryPropertiesOutcome?

    var generation: UInt64
    var activePhase: EntryPropertiesPhase?
    var appliedProposal: EntryPropertiesProposal?
    var pendingReadBack: EntryPropertiesProposal?
    var readBackProposal: EntryPropertiesProposal?

    public init(
        selection: EntryPropertiesSelection,
        status: EntryPropertiesStatus = .idle,
    ) {
        self.selection = selection
        self.status = status
        capabilityReport = nil
        targetSnapshot = nil
        proposal = nil
        canonicalResult = nil
        lastOutcome = nil
        generation = 0
        activePhase = nil
        appliedProposal = nil
        pendingReadBack = nil
        readBackProposal = nil
    }
}
