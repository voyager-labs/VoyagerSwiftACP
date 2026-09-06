import Foundation

public struct EntryPropertiesAction: Equatable, Sendable {
    enum Kind: Equatable {
        case selectionChanged(EntryPropertiesSelection)
        case discoverCapabilities
        case prepare(EntryPropertiesChangeIntent)
        case execute(confirmed: Bool)
        case retryReadBack
        case reconnect
        case cancel
        case discoveryCompleted(UInt64, Result<EntryPropertiesDiscovery, EntryPropertiesFailure>)
        case prepareCompleted(UInt64, Result<EntryPropertiesProposal, EntryPropertiesFailure>)
        case executeCompleted(UInt64, Result<EntryPropertiesExecutionReceipt, EntryPropertiesFailure>)
        case readBackCompleted(UInt64, Result<EntryPropertiesCanonicalResult, EntryPropertiesFailure>)
        case outcome(EntryPropertiesOutcome)
    }

    let kind: Kind

    public static func selectionChanged(_ selection: EntryPropertiesSelection) -> Self {
        Self(kind: .selectionChanged(selection))
    }

    public static let discoverCapabilities = Self(kind: .discoverCapabilities)

    public static func prepare(_ intent: EntryPropertiesChangeIntent) -> Self {
        Self(kind: .prepare(intent))
    }

    public static func execute(confirmed: Bool) -> Self {
        Self(kind: .execute(confirmed: confirmed))
    }

    public static let retryReadBack = Self(kind: .retryReadBack)
    public static let reconnect = Self(kind: .reconnect)
    public static let cancel = Self(kind: .cancel)

    public var outcome: EntryPropertiesOutcome? {
        guard case let .outcome(outcome) = kind else { return nil }
        return outcome
    }
}

struct EntryPropertiesDiscovery: Equatable {
    let snapshot: EntryPropertiesTargetSnapshot
    let capabilities: EntryPropertiesCapabilityReport
}

public struct EntryPropertiesExecutionReceipt: Equatable, Sendable {
    public let snapshot: EntryPropertiesTargetSnapshot

    public init(snapshot: EntryPropertiesTargetSnapshot) {
        self.snapshot = snapshot
    }
}
