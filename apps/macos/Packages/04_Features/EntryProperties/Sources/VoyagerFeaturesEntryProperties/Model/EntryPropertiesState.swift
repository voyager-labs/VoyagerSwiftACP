import ComposableArchitecture

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
