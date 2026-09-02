import Foundation

nonisolated public struct EntryCorePropertyClient: Sendable {
    public let definitionList: @Sendable (EntryCoreEndpoint, PropertyDefinitionListRequest) async throws
        -> PropertyDefinitionPage
    public let definitionCreate: @Sendable (EntryCoreEndpoint, PropertyDefinitionCreateRequest) async throws
        -> PropertyDefinition
    public let definitionUpdate: @Sendable (EntryCoreEndpoint, PropertyDefinitionUpdateRequest) async throws
        -> PropertyDefinition
    public let definitionDisable: @Sendable (EntryCoreEndpoint, PropertyDefinitionDisableRequest) async throws
        -> PropertyDefinition
    public let optionCreate: @Sendable (EntryCoreEndpoint, PropertyOptionCreateRequest) async throws
        -> PropertyDefinition
    public let optionUpdate: @Sendable (EntryCoreEndpoint, PropertyOptionUpdateRequest) async throws
        -> PropertyDefinition
    public let optionReorder: @Sendable (EntryCoreEndpoint, PropertyOptionReorderRequest) async throws
        -> PropertyDefinition
    public let optionDisable: @Sendable (EntryCoreEndpoint, PropertyOptionDisableRequest) async throws
        -> PropertyDefinition
    public let assignmentList: @Sendable (EntryCoreEndpoint, PropertyAssignmentListRequest) async throws
        -> PropertyAssignmentPage
    public let changePrepare: @Sendable (EntryCoreEndpoint, PropertyChangeRequest) async throws
        -> PropertyChangeProposal
    public let changeExecute: @Sendable (EntryCoreEndpoint, PropertyChangeRequest) async throws -> [PropertyAssignment]
    public let conditionQuery: @Sendable (EntryCoreEndpoint, PropertyConditionQueryRequest) async throws
        -> PropertyConditionQueryPage

    public init(
        definitionList: @escaping @Sendable (EntryCoreEndpoint, PropertyDefinitionListRequest) async throws
            -> PropertyDefinitionPage,
        definitionCreate: @escaping @Sendable (EntryCoreEndpoint, PropertyDefinitionCreateRequest) async throws
            -> PropertyDefinition,
        definitionUpdate: @escaping @Sendable (EntryCoreEndpoint, PropertyDefinitionUpdateRequest) async throws
            -> PropertyDefinition,
        definitionDisable: @escaping @Sendable (EntryCoreEndpoint, PropertyDefinitionDisableRequest) async throws
            -> PropertyDefinition,
        optionCreate: @escaping @Sendable (EntryCoreEndpoint, PropertyOptionCreateRequest) async throws
            -> PropertyDefinition,
        optionUpdate: @escaping @Sendable (EntryCoreEndpoint, PropertyOptionUpdateRequest) async throws
            -> PropertyDefinition,
        optionReorder: @escaping @Sendable (EntryCoreEndpoint, PropertyOptionReorderRequest) async throws
            -> PropertyDefinition,
        optionDisable: @escaping @Sendable (EntryCoreEndpoint, PropertyOptionDisableRequest) async throws
            -> PropertyDefinition,
        assignmentList: @escaping @Sendable (EntryCoreEndpoint, PropertyAssignmentListRequest) async throws
            -> PropertyAssignmentPage,
        changePrepare: @escaping @Sendable (EntryCoreEndpoint, PropertyChangeRequest) async throws
            -> PropertyChangeProposal,
        changeExecute: @escaping @Sendable (EntryCoreEndpoint, PropertyChangeRequest) async throws
            -> [PropertyAssignment],
        conditionQuery: @escaping @Sendable (EntryCoreEndpoint, PropertyConditionQueryRequest) async throws
            -> PropertyConditionQueryPage,
    ) {
        self.definitionList = definitionList
        self.definitionCreate = definitionCreate
        self.definitionUpdate = definitionUpdate
        self.definitionDisable = definitionDisable
        self.optionCreate = optionCreate
        self.optionUpdate = optionUpdate
        self.optionReorder = optionReorder
        self.optionDisable = optionDisable
        self.assignmentList = assignmentList
        self.changePrepare = changePrepare
        self.changeExecute = changeExecute
        self.conditionQuery = conditionQuery
    }
}

public extension EntryCorePropertyClient {
    nonisolated static var live: Self {
        makeLive(
            requestID: { UUID().uuidString },
            makeTransport: { { request, endpoint in try await UnixSocketTransport().request(request, to: endpoint) } },
        )
    }
}

extension EntryCorePropertyClient {
    nonisolated static func makeLive(
        requestID: @escaping @Sendable () -> String,
        makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
    ) -> Self {
        Self(
            definitionList: definitionPageOperation(requestID, makeTransport),
            definitionCreate: definitionOperation(.propertyDefinitionCreate, requestID, makeTransport),
            definitionUpdate: definitionOperation(.propertyDefinitionUpdate, requestID, makeTransport),
            definitionDisable: definitionOperation(.propertyDefinitionDisable, requestID, makeTransport),
            optionCreate: definitionOperation(.propertyOptionCreate, requestID, makeTransport),
            optionUpdate: definitionOperation(.propertyOptionUpdate, requestID, makeTransport),
            optionReorder: definitionOperation(.propertyOptionReorder, requestID, makeTransport),
            optionDisable: definitionOperation(.propertyOptionDisable, requestID, makeTransport),
            assignmentList: assignmentPageOperation(requestID, makeTransport),
            changePrepare: proposalOperation(requestID, makeTransport),
            changeExecute: executeOperation(requestID, makeTransport),
            conditionQuery: queryOperation(requestID, makeTransport),
        )
    }

    nonisolated private static func definitionPageOperation(
        _ requestID: @escaping @Sendable () -> String,
        _ makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
    ) -> @Sendable (EntryCoreEndpoint, PropertyDefinitionListRequest) async throws -> PropertyDefinitionPage {
        { endpoint, request in
            guard case let .definitionPage(value) = try await call(
                .propertyDefinitionList, endpoint, request, requestID, makeTransport,
            ) else { throw EntryCoreClientError.protocolMismatch }
            return value
        }
    }

    nonisolated private static func definitionOperation<Request: Encodable & Sendable>(
        _ method: EntryCoreMethod,
        _ requestID: @escaping @Sendable () -> String,
        _ makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
    ) -> @Sendable (EntryCoreEndpoint, Request) async throws -> PropertyDefinition {
        { endpoint, request in
            try await definition(method, endpoint, request, requestID, makeTransport)
        }
    }

    nonisolated private static func assignmentPageOperation(
        _ requestID: @escaping @Sendable () -> String,
        _ makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
    ) -> @Sendable (EntryCoreEndpoint, PropertyAssignmentListRequest) async throws -> PropertyAssignmentPage {
        { endpoint, request in
            guard case let .assignmentPage(value) = try await call(
                .propertyAssignmentList, endpoint, request, requestID, makeTransport,
            ) else { throw EntryCoreClientError.protocolMismatch }
            guard assignmentPageMatchesRequest(value, request: request) else {
                throw EntryCoreClientError.protocolMismatch
            }
            return value
        }
    }

    nonisolated private static func assignmentPageMatchesRequest(
        _ page: PropertyAssignmentPage,
        request: PropertyAssignmentListRequest,
    ) -> Bool {
        guard page.assignments.count <= request.pageSize else { return false }
        guard request.requestedPropertyIDs.isEmpty else {
            let requested = Set(request.requestedPropertyIDs)
            return page.assignments.allSatisfy { requested.contains($0.propertyID) }
        }
        return true
    }

    nonisolated private static func proposalOperation(
        _ requestID: @escaping @Sendable () -> String,
        _ makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
    ) -> @Sendable (EntryCoreEndpoint, PropertyChangeRequest) async throws -> PropertyChangeProposal {
        { endpoint, request in
            guard case let .proposal(value) = try await call(
                .propertyChangePrepare, endpoint, request, requestID, makeTransport,
            ) else { throw EntryCoreClientError.protocolMismatch }
            return value
        }
    }

    nonisolated private static func executeOperation(
        _ requestID: @escaping @Sendable () -> String,
        _ makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
    ) -> @Sendable (EntryCoreEndpoint, PropertyChangeRequest) async throws -> [PropertyAssignment] {
        { endpoint, request in
            guard case let .assignments(value) = try await call(
                .propertyChangeExecute, endpoint, request, requestID, makeTransport,
            ) else { throw EntryCoreClientError.protocolMismatch }
            guard executeAssignmentsMatchRequest(value, request: request) else {
                throw EntryCoreClientError.protocolMismatch
            }
            return value
        }
    }

    nonisolated private static func executeAssignmentsMatchRequest(
        _ assignments: [PropertyAssignment],
        request: PropertyChangeRequest,
    ) -> Bool {
        guard assignments.count == request.changes.count else { return false }
        return zip(assignments, request.changes).allSatisfy { assignment, change in
            assignment.propertyID == change.propertyID
        }
    }

    nonisolated private static func queryOperation(
        _ requestID: @escaping @Sendable () -> String,
        _ makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
    ) -> @Sendable (EntryCoreEndpoint, PropertyConditionQueryRequest) async throws -> PropertyConditionQueryPage {
        { endpoint, request in
            guard case let .queryPage(value) = try await call(
                .propertyConditionQuery, endpoint, request, requestID, makeTransport,
            ) else { throw EntryCoreClientError.protocolMismatch }
            guard queryPageMatchesRequest(value, request: request) else {
                throw EntryCoreClientError.protocolMismatch
            }
            return value
        }
    }

    nonisolated private static func queryPageMatchesRequest(
        _ page: PropertyConditionQueryPage,
        request: PropertyConditionQueryRequest,
    ) -> Bool {
        guard page.items.count <= request.pageSize else { return false }
        let requestedProjection = Set(request.projectionPropertyIDs)
        let itemIndices = Set(page.items.map(\.candidateIndex))
        let unresolvedIndices = Set(page.unresolvedCandidateIndices)
        guard page.items.allSatisfy({ item in
            item.candidateIndex < request.targets.count
                && item.projection.allSatisfy { requestedProjection.contains($0.propertyID) }
        }), page.unresolvedCandidateIndices.allSatisfy({ $0 < request.targets.count }),
        itemIndices.isDisjoint(with: unresolvedIndices) else { return false }
        return true
    }

    nonisolated private static func call(
        _ method: EntryCoreMethod,
        _ endpoint: EntryCoreEndpoint,
        _ params: some Encodable & Sendable,
        _ requestID: @Sendable () -> String,
        _ makeTransport: @Sendable () -> EntryCoreTransportRequest,
    ) async throws -> EntryCorePropertyDecodedResponse {
        let id = requestID()
        guard !id.isEmpty, id.utf8.count <= 128 else { throw EntryCoreClientError.localValidation }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let request: Data
        do { request = try encoder.encode(PropertyRequestWire(requestID: id, method: method.rawValue, params: params))
        } catch { throw EntryCoreClientError.localValidation }
        guard request.count <= StrictJSONParser.maximumWireBytes else {
            throw EntryCoreClientError.localValidation
        }
        let response = try await makeTransport()(request, endpoint)
        return try EntryCorePropertyResponseDecoder.decode(Array(response), method: method, expectedRequestID: id)
    }

    nonisolated private static func definition(
        _ method: EntryCoreMethod,
        _ endpoint: EntryCoreEndpoint,
        _ params: some Encodable & Sendable,
        _ requestID: @Sendable () -> String,
        _ makeTransport: @Sendable () -> EntryCoreTransportRequest,
    ) async throws -> PropertyDefinition {
        guard case let .definition(value) = try await call(method, endpoint, params, requestID, makeTransport)
        else { throw EntryCoreClientError.protocolMismatch }
        return value
    }
}

private struct PropertyRequestWire<Params: Encodable>: Encodable {
    let requestID: String
    let method: String
    let params: Params
    enum CodingKeys: String, CodingKey { case requestID = "request_id", method, params }
}
