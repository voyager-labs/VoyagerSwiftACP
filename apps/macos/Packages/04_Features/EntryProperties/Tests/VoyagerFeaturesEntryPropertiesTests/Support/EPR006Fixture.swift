@testable import VoyagerFeaturesEntryProperties

struct Fixture {
    let selection = EntryPropertiesSelection(
        targets: [.init(localPath: "/a"), .init(localPath: "/b")],
        propertyID: .init(rawValue: "property-a"),
    )
    let catalog = EntryPropertiesCatalog(version: "2.2.0")
    let intent = EntryPropertiesChangeIntent(change: .set(.text("after")), isDestructive: false)

    var assignments: EntryPropertiesAssignments {
        .init(
            canonicalRevision: 7,
            values: selection.targets.map { .init(target: $0, value: .text("before"), revision: 7) },
        )
    }

    var snapshot: EntryPropertiesTargetSnapshot {
        .init(
            reconcilingTargets: selection.targets,
            propertyID: selection.propertyID,
            catalogVersion: catalog.version ?? "2.2.0",
            canonicalRevision: assignments.canonicalRevision,
            definitionRevision: catalog.definitionRevision,
            valueKind: catalog.valueKind,
            cardinality: catalog.cardinality,
            assignmentRevisions: assignments.values.map {
                .init(target: $0.target, revision: $0.revision)
            },
        )
    }

    var capabilityReport: EntryPropertiesCapabilityReport {
        .init(
            items: [
                .init(operation: .changeValue, capability: .supported),
                .init(operation: .validate, capability: .supported),
            ],
            supportsMultipleTargets: true,
            catalogVersion: "2.2.0",
        )
    }

    var proposal: EntryPropertiesProposal {
        .init(
            snapshot: snapshot,
            intent: intent,
            differences: selection.targets.map {
                .init(target: $0, before: .text("before"), after: .text("after"))
            },
            affectedTargetCount: selection.targets.count,
            validation: .init(isValid: true),
            requiresConfirmation: true,
        )
    }

    var canonicalResult: EntryPropertiesCanonicalResult {
        .init(
            snapshot: snapshot,
            values: selection.targets.map { .init(target: $0, value: .text("after"), revision: 8) },
        )
    }

    /// 검증 성공 뒤 reducer가 canonical result revision으로 갱신하는 snapshot이다.
    /// 같은 selection 연속 편집이 이 revision을 CAS 토큰으로 사용한다.
    var verifiedSnapshot: EntryPropertiesTargetSnapshot {
        .init(
            reconcilingTargets: selection.targets,
            propertyID: selection.propertyID,
            catalogVersion: catalog.version ?? "2.2.0",
            canonicalRevision: 8,
            definitionRevision: catalog.definitionRevision,
            valueKind: catalog.valueKind,
            cardinality: catalog.cardinality,
            assignmentRevisions: selection.targets.map { .init(target: $0, revision: 8) },
        )
    }

    var readyState: EntryPropertiesState {
        var state = EntryPropertiesState(selection: selection, status: .ready)
        state.targetSnapshot = snapshot
        state.capabilityReport = capabilityReport
        return state
    }

    func client(
        prepare: @escaping @Sendable (EntryPropertiesPrepareRequest) async throws -> EntryPropertiesProposal = { _ in
            throw EntryPropertiesFailure.unavailable
        },
        execute: @escaping @Sendable (EntryPropertiesProposal) async throws -> EntryPropertiesExecutionReceipt = { _ in
            throw EntryPropertiesFailure.unavailable
        },
        readBack: @escaping @Sendable (
            EntryPropertiesReadBackRequest,
        ) async throws -> EntryPropertiesCanonicalResult = { _ in throw EntryPropertiesFailure.unavailable },
    ) -> EntryPropertiesClient {
        EntryPropertiesClient(
            loadCatalog: { _ in throw EntryPropertiesFailure.unavailable },
            loadAssignments: { _, _ in throw EntryPropertiesFailure.unavailable },
            discoverCapabilities: { _ in throw EntryPropertiesFailure.unavailable },
            prepare: prepare,
            execute: execute,
            readBack: readBack,
        )
    }
}
