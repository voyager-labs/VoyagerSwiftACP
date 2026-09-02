import Foundation

public struct EntryPropertiesTarget: Equatable, Hashable, Sendable {
    public let localPath: String

    public init(localPath: String) {
        self.localPath = localPath
    }
}

public struct EntryPropertiesPropertyID: Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum EntryPropertiesValue: Equatable, Sendable {
    case unset
    case null
    case text(String)
    case number(String)
    case date(String)
    case dateTime(String)
    case boolean(Bool)
    case selection([String])
    case texts([String])
    case numbers([String])
    case dates([String])
    case dateTimes([String])
    case booleans([Bool])
}

public enum EntryPropertiesValueKind: Equatable, Sendable {
    case text
    case number
    case date
    case dateTime
    case boolean
    case selection
}

public enum EntryPropertiesCardinality: Equatable, Sendable {
    case one
    case many
}

public enum EntryPropertiesOperation: Equatable, Hashable, Sendable {
    case readValue
    case changeValue
    case changeDefinition
    case changeOptions
    case changeDisplay
    case validate
}

public enum EntryPropertiesCapability: Equatable, Sendable {
    case unknown
    case supported
    case unsupported(EntryPropertiesFailure)
}

public struct EntryPropertiesCapabilityItem: Equatable, Sendable {
    public let operation: EntryPropertiesOperation
    public let capability: EntryPropertiesCapability

    public init(operation: EntryPropertiesOperation, capability: EntryPropertiesCapability) {
        self.operation = operation
        self.capability = capability
    }
}

public struct EntryPropertiesCapabilityReport: Equatable, Sendable {
    public let items: [EntryPropertiesCapabilityItem]
    public let supportsMultipleTargets: Bool
    public let catalogVersion: String?

    public init(
        items: [EntryPropertiesCapabilityItem],
        supportsMultipleTargets: Bool,
        catalogVersion: String? = nil,
    ) {
        self.items = items
        self.supportsMultipleTargets = supportsMultipleTargets
        self.catalogVersion = catalogVersion
    }

    public func capability(for operation: EntryPropertiesOperation) -> EntryPropertiesCapability {
        items.first(where: { $0.operation == operation })?.capability ?? .unknown
    }
}

public struct EntryPropertiesSelection: Equatable, Sendable {
    public let targets: [EntryPropertiesTarget]
    public let propertyID: EntryPropertiesPropertyID

    public init(targets: [EntryPropertiesTarget], propertyID: EntryPropertiesPropertyID) {
        self.targets = targets
        self.propertyID = propertyID
    }
}

public struct EntryPropertiesTargetSnapshot: Equatable, Sendable {
    public let targets: [EntryPropertiesTarget]
    public let propertyID: EntryPropertiesPropertyID
    public let catalogVersion: String
    public let canonicalRevision: Int64
    let definitionRevision: Int64
    let valueKind: EntryPropertiesValueKind
    let cardinality: EntryPropertiesCardinality
    let assignmentRevisions: [EntryPropertiesTargetRevision]

    public init(
        targets: [EntryPropertiesTarget],
        propertyID: EntryPropertiesPropertyID,
        catalogVersion: String,
        canonicalRevision: Int64,
    ) {
        self.targets = targets
        self.propertyID = propertyID
        self.catalogVersion = catalogVersion
        self.canonicalRevision = canonicalRevision
        definitionRevision = 1
        valueKind = .text
        cardinality = .one
        assignmentRevisions = []
    }

    init(
        reconcilingTargets targets: [EntryPropertiesTarget],
        propertyID: EntryPropertiesPropertyID,
        catalogVersion: String,
        canonicalRevision: Int64,
        definitionRevision: Int64,
        valueKind: EntryPropertiesValueKind,
        cardinality: EntryPropertiesCardinality,
        assignmentRevisions: [EntryPropertiesTargetRevision],
    ) {
        self.targets = targets
        self.propertyID = propertyID
        self.catalogVersion = catalogVersion
        self.canonicalRevision = canonicalRevision
        self.definitionRevision = definitionRevision
        self.valueKind = valueKind
        self.cardinality = cardinality
        self.assignmentRevisions = assignmentRevisions
    }
}

struct EntryPropertiesTargetRevision: Equatable {
    let target: EntryPropertiesTarget
    let revision: Int64
}

public struct EntryPropertiesCatalog: Equatable, Sendable {
    public let version: String?
    public let definitionRevision: Int64
    public let valueKind: EntryPropertiesValueKind
    public let cardinality: EntryPropertiesCardinality

    public init(
        version: String? = nil,
        definitionRevision: Int64 = 1,
        valueKind: EntryPropertiesValueKind = .text,
        cardinality: EntryPropertiesCardinality = .one,
    ) {
        self.version = version
        self.definitionRevision = definitionRevision
        self.valueKind = valueKind
        self.cardinality = cardinality
    }
}

public struct EntryPropertiesAssignments: Equatable, Sendable {
    public let canonicalRevision: Int64
    public let values: [EntryPropertiesCanonicalValue]

    public init(canonicalRevision: Int64, values: [EntryPropertiesCanonicalValue]) {
        self.canonicalRevision = canonicalRevision
        self.values = values
    }
}

public struct EntryPropertiesCapabilityRequest: Equatable, Sendable {
    public let selection: EntryPropertiesSelection
    public let catalog: EntryPropertiesCatalog
    public let assignments: EntryPropertiesAssignments

    public init(
        selection: EntryPropertiesSelection,
        catalog: EntryPropertiesCatalog,
        assignments: EntryPropertiesAssignments,
    ) {
        self.selection = selection
        self.catalog = catalog
        self.assignments = assignments
    }
}

public struct EntryPropertiesPrepareRequest: Equatable, Sendable {
    public let snapshot: EntryPropertiesTargetSnapshot
    public let intent: EntryPropertiesChangeIntent

    public init(snapshot: EntryPropertiesTargetSnapshot, intent: EntryPropertiesChangeIntent) {
        self.snapshot = snapshot
        self.intent = intent
    }
}

public struct EntryPropertiesReadBackRequest: Equatable, Sendable {
    public let snapshot: EntryPropertiesTargetSnapshot

    public init(snapshot: EntryPropertiesTargetSnapshot) {
        self.snapshot = snapshot
    }
}

public enum EntryPropertiesChange: Equatable, Sendable {
    case set(EntryPropertiesValue)
    case unset
}

public struct EntryPropertiesChangeIntent: Equatable, Sendable {
    public let change: EntryPropertiesChange
    public let isDestructive: Bool

    public init(change: EntryPropertiesChange, isDestructive: Bool = false) {
        self.change = change
        self.isDestructive = isDestructive
    }
}

public struct EntryPropertiesDifference: Equatable, Sendable {
    public let target: EntryPropertiesTarget
    public let before: EntryPropertiesValue
    public let after: EntryPropertiesValue

    public init(target: EntryPropertiesTarget, before: EntryPropertiesValue, after: EntryPropertiesValue) {
        self.target = target
        self.before = before
        self.after = after
    }
}

public struct EntryPropertiesValidation: Equatable, Sendable {
    public let isValid: Bool
    public let failure: EntryPropertiesFailure?

    public init(isValid: Bool, failure: EntryPropertiesFailure? = nil) {
        self.isValid = isValid
        self.failure = failure
    }
}

public struct EntryPropertiesProposal: Equatable, Sendable {
    public let snapshot: EntryPropertiesTargetSnapshot
    public let intent: EntryPropertiesChangeIntent
    public let differences: [EntryPropertiesDifference]
    public let affectedTargetCount: Int
    public let validation: EntryPropertiesValidation
    public let requiresConfirmation: Bool

    public init(
        snapshot: EntryPropertiesTargetSnapshot,
        intent: EntryPropertiesChangeIntent,
        differences: [EntryPropertiesDifference],
        affectedTargetCount: Int,
        validation: EntryPropertiesValidation,
        requiresConfirmation: Bool,
    ) {
        self.snapshot = snapshot
        self.intent = intent
        self.differences = differences
        self.affectedTargetCount = affectedTargetCount
        self.validation = validation
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct EntryPropertiesCanonicalValue: Equatable, Sendable {
    public let target: EntryPropertiesTarget
    public let value: EntryPropertiesValue
    public let revision: Int64

    public init(target: EntryPropertiesTarget, value: EntryPropertiesValue, revision: Int64) {
        self.target = target
        self.value = value
        self.revision = revision
    }
}

public struct EntryPropertiesCanonicalResult: Equatable, Sendable {
    public let snapshot: EntryPropertiesTargetSnapshot
    public let values: [EntryPropertiesCanonicalValue]

    public init(snapshot: EntryPropertiesTargetSnapshot, values: [EntryPropertiesCanonicalValue]) {
        self.snapshot = snapshot
        self.values = values
    }
}

public enum EntryPropertiesFailure: Error, Equatable, Sendable {
    case validation
    case conflict
    case unsupported
    case unavailable
    case authorization
    case busy
    case stale
    case confirmationRequired
    case ambiguousExecution
}

public enum EntryPropertiesStatus: Equatable, Sendable {
    case idle
    case discovering
    case ready
    case preparing
    case prepared
    case executing
    case applied
    case appliedUnverified
    case verified
    case rejected(EntryPropertiesFailure)
    case ambiguous
}

public enum EntryPropertiesOutcome: Equatable, Sendable {
    case capabilitiesDiscovered(EntryPropertiesCapabilityReport)
    case propertyChangePrepared(EntryPropertiesProposal)
    case propertyChangeApplied(EntryPropertiesTargetSnapshot)
    case propertyChangeAppliedUnverified(EntryPropertiesTargetSnapshot)
    case propertyChangeVerified(EntryPropertiesCanonicalResult)
    case propertyChangeRejected(EntryPropertiesFailure)
    case propertyChangeConflict
    case propertyChangeUnsupported
}
