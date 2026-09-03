import Dependencies
import Foundation
import VoyagerEntryCoreClient

public struct EntryPropertiesClient: Sendable {
    public var loadCatalog: @Sendable (EntryPropertiesSelection) async throws -> EntryPropertiesCatalog
    public var loadAssignments: @Sendable (
        EntryPropertiesSelection,
        EntryPropertiesCatalog,
    ) async throws -> EntryPropertiesAssignments
    public var discoverCapabilities: @Sendable (
        EntryPropertiesCapabilityRequest,
    ) async throws -> EntryPropertiesCapabilityReport
    public var prepare: @Sendable (EntryPropertiesPrepareRequest) async throws -> EntryPropertiesProposal
    public var execute: @Sendable (EntryPropertiesProposal) async throws -> EntryPropertiesExecutionReceipt
    public var readBack: @Sendable (EntryPropertiesReadBackRequest) async throws -> EntryPropertiesCanonicalResult

    public init(
        loadCatalog: @escaping @Sendable (EntryPropertiesSelection) async throws -> EntryPropertiesCatalog,
        loadAssignments: @escaping @Sendable (
            EntryPropertiesSelection,
            EntryPropertiesCatalog,
        ) async throws -> EntryPropertiesAssignments,
        discoverCapabilities: @escaping @Sendable (
            EntryPropertiesCapabilityRequest,
        ) async throws -> EntryPropertiesCapabilityReport,
        prepare: @escaping @Sendable (EntryPropertiesPrepareRequest) async throws -> EntryPropertiesProposal,
        execute: @escaping @Sendable (EntryPropertiesProposal) async throws -> EntryPropertiesExecutionReceipt,
        readBack: @escaping @Sendable (EntryPropertiesReadBackRequest) async throws -> EntryPropertiesCanonicalResult,
    ) {
        self.loadCatalog = loadCatalog
        self.loadAssignments = loadAssignments
        self.discoverCapabilities = discoverCapabilities
        self.prepare = prepare
        self.execute = execute
        self.readBack = readBack
    }
}

extension EntryPropertiesClient: DependencyKey {
    public static let liveValue = EntryPropertiesClient.unavailable
    public static let testValue = EntryPropertiesClient.unavailable
    public static let previewValue = EntryPropertiesClient.unavailable

    public static let unavailable = EntryPropertiesClient(
        loadCatalog: { _ in throw EntryPropertiesFailure.unavailable },
        loadAssignments: { _, _ in throw EntryPropertiesFailure.unavailable },
        discoverCapabilities: { _ in throw EntryPropertiesFailure.unavailable },
        prepare: { _ in throw EntryPropertiesFailure.unavailable },
        execute: { _ in throw EntryPropertiesFailure.unavailable },
        readBack: { _ in throw EntryPropertiesFailure.unavailable },
    )
}

public extension DependencyValues {
    var entryPropertiesClient: EntryPropertiesClient {
        get { self[EntryPropertiesClient.self] }
        set { self[EntryPropertiesClient.self] = newValue }
    }
}

/// Entry Core Property transport를 EPR-006의 의미 기반 dependency로 연결하는 유일한 생성 경계다.
public enum EntryPropertiesClientFactory {
    public typealias CapabilityDiscovery = @Sendable (
        EntryPropertiesCapabilityRequest,
    ) async throws -> EntryPropertiesCapabilityReport

    public static func live(
        propertyClient: EntryCorePropertyClient,
        endpoint: EntryCoreEndpoint,
        capabilityDiscovery: @escaping CapabilityDiscovery,
    ) -> EntryPropertiesClient {
        EntryPropertiesClient(
            loadCatalog: { selection in
                try await loadCatalog(propertyClient: propertyClient, endpoint: endpoint, selection: selection)
            },
            loadAssignments: { selection, catalog in
                try await loadAssignments(
                    propertyClient: propertyClient,
                    endpoint: endpoint,
                    selection: selection,
                    catalog: catalog,
                )
            },
            discoverCapabilities: capabilityDiscovery,
            prepare: { request in
                try await prepare(
                    propertyClient: propertyClient,
                    endpoint: endpoint,
                    request: request,
                )
            },
            execute: { proposal in
                try await execute(propertyClient: propertyClient, endpoint: endpoint, proposal: proposal)
            },
            readBack: { request in
                try await readBack(propertyClient: propertyClient, endpoint: endpoint, request: request)
            },
        )
    }

    private static func prepare(
        propertyClient: EntryCorePropertyClient,
        endpoint: EntryCoreEndpoint,
        request: EntryPropertiesPrepareRequest,
    ) async throws -> EntryPropertiesProposal {
        let changes = try makeWireChanges(snapshot: request.snapshot, intent: request.intent)
        let proposal = try await propertyClient.changePrepare(endpoint, PropertyChangeRequest(changes: changes))
        guard proposal.changes.count == changes.count,
              zip(proposal.changes, changes).allSatisfy({ prepared, requested in
                  prepared.target.localPath == requested.target.localPath
                      && prepared.propertyID == requested.propertyID
                      && prepared.after == requested.desired
              })
        else {
            throw EntryPropertiesFailure.validation
        }
        let differences = try proposal.changes.map { change in
            let target = EntryPropertiesTarget(localPath: change.target.localPath)
            return try EntryPropertiesDifference(
                target: target,
                before: semanticValue(change.before),
                after: semanticValue(change.after),
            )
        }
        return EntryPropertiesProposal(
            snapshot: request.snapshot,
            intent: request.intent,
            differences: differences,
            affectedTargetCount: differences.count,
            validation: .init(isValid: true),
            requiresConfirmation: proposal.requiresConfirmation
                || request.intent.isDestructive
                || request.snapshot.targets.count > 1,
        )
    }

    private static func execute(
        propertyClient: EntryCorePropertyClient,
        endpoint: EntryCoreEndpoint,
        proposal: EntryPropertiesProposal,
    ) async throws -> EntryPropertiesExecutionReceipt {
        let changes = try makeWireChanges(snapshot: proposal.snapshot, intent: proposal.intent)
        _ = try await propertyClient.changeExecute(endpoint, PropertyChangeRequest(changes: changes))
        return EntryPropertiesExecutionReceipt(snapshot: proposal.snapshot)
    }

    private static func readBack(
        propertyClient: EntryCorePropertyClient,
        endpoint: EntryCoreEndpoint,
        request: EntryPropertiesReadBackRequest,
    ) async throws -> EntryPropertiesCanonicalResult {
        let snapshot = request.snapshot
        let selection = EntryPropertiesSelection(targets: snapshot.targets, propertyID: snapshot.propertyID)
        let catalog = EntryPropertiesCatalog(
            version: snapshot.catalogVersion,
            definitionRevision: snapshot.definitionRevision,
            valueKind: snapshot.valueKind,
            cardinality: snapshot.cardinality,
        )
        let assignments = try await loadAssignments(
            propertyClient: propertyClient,
            endpoint: endpoint,
            selection: selection,
            catalog: catalog,
        )
        return EntryPropertiesCanonicalResult(snapshot: snapshot, values: assignments.values)
    }

    private static func loadCatalog(
        propertyClient: EntryCorePropertyClient,
        endpoint: EntryCoreEndpoint,
        selection: EntryPropertiesSelection,
    ) async throws -> EntryPropertiesCatalog {
        let propertyID = try PropertyID(rawValue: selection.propertyID.rawValue)
        var pageToken: String?
        repeat {
            let request = try PropertyDefinitionListRequest(
                pageSize: 256,
                requestedPropertyIDs: [propertyID],
                includeDisabled: true,
                pageToken: pageToken,
            )
            let page = try await propertyClient.definitionList(endpoint, request)
            if let definition = page.definitions.first(where: { $0.id == propertyID }) {
                let version: String? = switch definition.conditionCapability {
                case let .supported(catalogVersion, _, _): catalogVersion
                case .unsupported: nil
                }
                return EntryPropertiesCatalog(
                    version: version,
                    definitionRevision: definition.revision,
                    valueKind: semanticValueKind(definition.valueType),
                    cardinality: semanticCardinality(definition.cardinality),
                )
            }
            pageToken = page.nextPageToken
            if !page.hasMore { break }
        } while pageToken != nil
        throw EntryPropertiesFailure.unavailable
    }

    private static func loadAssignments(
        propertyClient: EntryCorePropertyClient,
        endpoint: EntryCoreEndpoint,
        selection: EntryPropertiesSelection,
        catalog: EntryPropertiesCatalog,
    ) async throws -> EntryPropertiesAssignments {
        let propertyID = try PropertyID(rawValue: selection.propertyID.rawValue)
        var values: [EntryPropertiesCanonicalValue] = []
        values.reserveCapacity(selection.targets.count)
        for target in selection.targets {
            let wireTarget = try PropertyTarget(localPath: target.localPath)
            var pageToken: String?
            var resolved: PropertyAssignment?
            repeat {
                let request = try PropertyAssignmentListRequest(
                    pageSize: 256,
                    requestedPropertyIDs: [propertyID],
                    target: wireTarget,
                    pageToken: pageToken,
                )
                let page = try await propertyClient.assignmentList(endpoint, request)
                resolved = page.assignments.first(where: { $0.propertyID == propertyID })
                if resolved != nil || !page.hasMore { break }
                pageToken = page.nextPageToken
            } while pageToken != nil

            if let resolved {
                // daemon이 정확한 property ID를 담아도 catalog value contract와
                // 다른 value type/cardinality를 반환하면 snapshot 계약과 모순되는
                // canonical baseline이 만들어지므로 fail-closed로 거절한다.
                guard semanticValueKind(resolved.valueType) == catalog.valueKind,
                      semanticCardinality(resolved.cardinality) == catalog.cardinality
                else {
                    throw EntryPropertiesFailure.validation
                }
                try values.append(
                    .init(
                        target: target,
                        value: semanticValue(resolved),
                        revision: resolved.revision,
                    ),
                )
            } else {
                values.append(.init(target: target, value: .unset, revision: 0))
            }
        }
        return EntryPropertiesAssignments(
            canonicalRevision: values.map(\.revision).max() ?? 0,
            values: values,
        )
    }

    private static func makeWireChanges(
        snapshot: EntryPropertiesTargetSnapshot,
        intent: EntryPropertiesChangeIntent,
    ) throws -> [PropertyChangeTarget] {
        let propertyID = try PropertyID(rawValue: snapshot.propertyID.rawValue)
        let desired = try wireDesiredState(intent.change, snapshot: snapshot)
        return try snapshot.targets.map { target in
            let assignmentRevision = snapshot.assignmentRevisions
                .first(where: { $0.target == target })?.revision ?? snapshot.canonicalRevision
            return try PropertyChangeTarget(
                target: PropertyTarget(localPath: target.localPath),
                propertyID: propertyID,
                expectedDefinitionRevision: snapshot.definitionRevision,
                expectedAssignmentRevision: assignmentRevision,
                desired: desired,
            )
        }
    }

    private static func wireDesiredState(
        _ change: EntryPropertiesChange,
        snapshot: EntryPropertiesTargetSnapshot,
    ) throws -> PropertyDesiredState {
        guard case let .set(value) = change else { return .unknown }
        switch snapshot.cardinality {
        case .one: return try wireScalarValue(value)
        case .many: return try wireManyValue(value)
        }
    }

    private static func wireScalarValue(_ value: EntryPropertiesValue) throws -> PropertyDesiredState {
        switch value {
        case .unset: return .unknown
        case .null: return .null
        case let .text(value): return .value(.text, .one, .text(value))
        case let .number(value): return .value(.number, .one, .number(value))
        case let .date(value): return .value(.date, .one, .date(value))
        case let .dateTime(value): return .value(.datetime, .one, .dateTime(value))
        case let .boolean(value): return .value(.boolean, .one, .boolean(value))
        case let .selection(values):
            let optionIDs = try values.map(PropertyOptionID.init(rawValue:))
            guard let optionID = optionIDs.only else { throw EntryPropertiesFailure.validation }
            return .value(.select, .one, .select(optionID))
        case .texts, .numbers, .dates, .dateTimes, .booleans:
            throw EntryPropertiesFailure.validation
        }
    }

    private static func wireManyValue(_ value: EntryPropertiesValue) throws -> PropertyDesiredState {
        switch value {
        case .unset: return .unknown
        case .null: return .null
        case let .selection(values):
            return try .value(.select, .many, .selects(values.map(PropertyOptionID.init(rawValue:))))
        case let .texts(values): return .value(.text, .many, .texts(values))
        case let .numbers(values): return .value(.number, .many, .numbers(values))
        case let .dates(values): return .value(.date, .many, .dates(values))
        case let .dateTimes(values): return .value(.datetime, .many, .dateTimes(values))
        case let .booleans(values): return .value(.boolean, .many, .booleans(values))
        case .text, .number, .date, .dateTime, .boolean:
            throw EntryPropertiesFailure.validation
        }
    }

    private static func semanticValue(_ assignment: PropertyAssignment?) throws -> EntryPropertiesValue {
        guard let assignment else { return .unset }
        switch assignment.state {
        case .null: return .null
        case .unknown, .notApplicable: return .unset
        case .value:
            guard let value = assignment.value else { throw EntryPropertiesFailure.validation }
            return try semanticValue(value)
        }
    }

    private static func semanticValue(_ desired: PropertyDesiredState) throws -> EntryPropertiesValue {
        switch desired {
        case .null: .null
        case .unknown, .notApplicable: .unset
        case let .value(_, _, value): try semanticValue(value)
        }
    }

    private static func semanticValue(_ value: PropertyValue) throws -> EntryPropertiesValue {
        switch value {
        case let .text(value): .text(value)
        case let .number(value): .number(value)
        case let .date(value): .date(value)
        case let .dateTime(value): .dateTime(value)
        case let .boolean(value): .boolean(value)
        case let .select(value): .selection([value.rawValue])
        default: try semanticManyValue(value)
        }
    }

    private static func semanticManyValue(_ value: PropertyValue) throws -> EntryPropertiesValue {
        switch value {
        case let .texts(values): .texts(values)
        case let .numbers(values): .numbers(values)
        case let .dates(values): .dates(values)
        case let .dateTimes(values): .dateTimes(values)
        case let .booleans(values): .booleans(values)
        case let .selects(values): .selection(values.map(\.rawValue))
        default: throw EntryPropertiesFailure.validation
        }
    }

    private static func semanticValueKind(_ valueType: PropertyValueType) -> EntryPropertiesValueKind {
        switch valueType {
        case .text: .text
        case .number: .number
        case .date: .date
        case .datetime: .dateTime
        case .boolean: .boolean
        case .select: .selection
        }
    }

    private static func semanticCardinality(_ cardinality: PropertyCardinality) -> EntryPropertiesCardinality {
        switch cardinality {
        case .one: .one
        case .many: .many
        }
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
