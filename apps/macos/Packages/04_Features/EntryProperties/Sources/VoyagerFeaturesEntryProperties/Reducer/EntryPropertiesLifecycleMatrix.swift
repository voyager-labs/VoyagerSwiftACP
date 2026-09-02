enum EntryPropertiesOperationPhase: CaseIterable, Hashable {
    case discover
    case prepare
    case execute
    case readBack
}

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

enum EntryPropertiesFreshness: CaseIterable, Hashable {
    case current
    case stale
}

enum EntryPropertiesActiveEffect: CaseIterable, Hashable {
    case none
    case matching
    case different
}

enum EntryPropertiesCompletionTrust: CaseIterable, Hashable {
    case trusted
    case rejected
    case ambiguous
}

enum EntryPropertiesLifecycleDisposition: Equatable {
    case accept
    case ignoreLate
    case rejectBusy
    case recoverReadOnly
    case preserveAmbiguity
}

struct EntryPropertiesLifecycleCase: Hashable {
    let operation: EntryPropertiesOperationPhase
    let phase: EntryPropertiesPhase
    let freshness: EntryPropertiesFreshness
    let activeEffect: EntryPropertiesActiveEffect
    let trust: EntryPropertiesCompletionTrust
}

enum EntryPropertiesLifecycleMatrix {
    static let allCases: [EntryPropertiesLifecycleCase] = EntryPropertiesOperationPhase.allCases.flatMap { operation in
        EntryPropertiesPhase.allCases.flatMap { phase in
            EntryPropertiesFreshness.allCases.flatMap { freshness in
                EntryPropertiesActiveEffect.allCases.flatMap { activeEffect in
                    EntryPropertiesCompletionTrust.allCases.map { trust in
                        EntryPropertiesLifecycleCase(
                            operation: operation,
                            phase: phase,
                            freshness: freshness,
                            activeEffect: activeEffect,
                            trust: trust,
                        )
                    }
                }
            }
        }
    }

    static func disposition(for lifecycleCase: EntryPropertiesLifecycleCase) -> EntryPropertiesLifecycleDisposition {
        guard lifecycleCase.freshness == .current else { return .ignoreLate }
        guard lifecycleCase.activeEffect != .different else { return .rejectBusy }
        if lifecycleCase.operation == .execute, lifecycleCase.trust == .ambiguous {
            return .preserveAmbiguity
        }
        if lifecycleCase.operation == .readBack,
           lifecycleCase.phase == .appliedUnverified,
           lifecycleCase.trust != .trusted
        {
            return .recoverReadOnly
        }
        guard lifecycleCase.activeEffect == .matching else { return .ignoreLate }
        return .accept
    }
}
