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
            definitionCreate: definitionOperation(
                .propertyDefinitionCreate,
                requestID,
                makeTransport,
                validate: definitionCreateMatchesResponse,
            ),
            definitionUpdate: definitionOperation(
                .propertyDefinitionUpdate,
                requestID,
                makeTransport,
                validate: definitionUpdateMatchesResponse,
            ),
            definitionDisable: definitionOperation(
                .propertyDefinitionDisable,
                requestID,
                makeTransport,
                validate: definitionDisableMatchesResponse,
            ),
            optionCreate: definitionOperation(
                .propertyOptionCreate,
                requestID,
                makeTransport,
                validate: optionCreateMatchesResponse,
            ),
            optionUpdate: definitionOperation(
                .propertyOptionUpdate,
                requestID,
                makeTransport,
                validate: optionUpdateMatchesResponse,
            ),
            optionReorder: definitionOperation(
                .propertyOptionReorder,
                requestID,
                makeTransport,
                validate: optionReorderMatchesResponse,
            ),
            optionDisable: definitionOperation(
                .propertyOptionDisable,
                requestID,
                makeTransport,
                validate: optionDisableMatchesResponse,
            ),
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
            guard definitionPageMatchesRequest(value, request: request) else {
                throw EntryCoreClientError.protocolMismatch
            }
            return value
        }
    }

    nonisolated private static func definitionPageMatchesRequest(
        _ page: PropertyDefinitionPage,
        request: PropertyDefinitionListRequest,
    ) -> Bool {
        guard page.definitions.count <= request.pageSize else { return false }
        if !request.requestedPropertyIDs.isEmpty {
            let requested = Set(request.requestedPropertyIDs)
            guard page.definitions.allSatisfy({ requested.contains($0.id) }) else { return false }
        }
        guard request.includeDisabled == true || page.definitions.allSatisfy({ $0.state != .disabled }) else {
            return false
        }
        // has_more인 페이지는 page_size를 정확히 채우고 전진하는 token을 가져야
        // 한다(저장소가 limit+1행으로 판정한다). 같은 token의 반복은 페이지
        // 순회 caller를 끝내지 못하게 하므로 거절한다.
        guard page.hasMore else { return true }
        return page.definitions.count == request.pageSize
            && page.nextPageToken != nil
            && page.nextPageToken != request.pageToken
    }

    nonisolated private static func definitionOperation<Request: Encodable & Sendable>(
        _ method: EntryCoreMethod,
        _ requestID: @escaping @Sendable () -> String,
        _ makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
        validate: @escaping @Sendable (PropertyDefinition, Request) -> Bool,
    ) -> @Sendable (EntryCoreEndpoint, Request) async throws -> PropertyDefinition {
        { endpoint, request in
            let value = try await definition(method, endpoint, request, requestID, makeTransport)
            guard validate(value, request) else { throw EntryCoreClientError.protocolMismatch }
            return value
        }
    }

    nonisolated private static func definitionCreateMatchesResponse(
        _ definition: PropertyDefinition,
        request: PropertyDefinitionCreateRequest,
    ) -> Bool {
        let requestedLabels = request.options?.map(\.label) ?? []
        let responseOptions = definition.options.sorted { $0.position < $1.position }
        // 새 definition은 항상 user-defined로 생성된다(CatalogService.CreateDefinition).
        // built-in origin 응답은 요청과 무관한 ownership이므로 승인하지 않는다.
        return definition.origin == .userDefined
            && definition.state == .active
            && definition.revision == 1
            && definition.key == request.key
            && definition.name == request.name
            && definition.valueType == request.valueType
            && definition.cardinality == request.cardinality
            && responseOptions.map(\.label) == requestedLabels
            && responseOptions.enumerated().allSatisfy { index, option in
                option.state == .active && option.position == index + 1
            }
    }

    nonisolated private static func definitionUpdateMatchesResponse(
        _ definition: PropertyDefinition,
        request: PropertyDefinitionUpdateRequest,
    ) -> Bool {
        // applyDefinitionUpdate는 표시 이름 외 필드를 불변으로 강제한다. 사전
        // definition snapshot에서 이름·revision만 바뀐 응답만 승인한다.
        guard definitionMutationRevisionMatches(
            definition,
            propertyID: request.propertyID,
            expectedDefinitionRevision: request.expectedDefinitionRevision,
        ) else { return false }
        let expected = mutatedDefinitionSnapshot(
            request.expectedDefinition,
            name: request.name,
            state: .active,
            revision: request.expectedDefinitionRevision + 1,
        )
        return definition == expected
    }

    nonisolated private static func definitionDisableMatchesResponse(
        _ definition: PropertyDefinition,
        request: PropertyDefinitionDisableRequest,
    ) -> Bool {
        // DisableDefinition은 lifecycle만 변경한다. 이름·value contract·
        // options가 함께 바뀐 응답은 정상 daemon에서 생성될 수 없다.
        guard definitionMutationRevisionMatches(
            definition,
            propertyID: request.propertyID,
            expectedDefinitionRevision: request.expectedDefinitionRevision,
            state: .disabled,
        ) else { return false }
        let expected = mutatedDefinitionSnapshot(
            request.expectedDefinition,
            name: nil,
            state: .disabled,
            revision: request.expectedDefinitionRevision + 1,
        )
        return definition == expected
    }

    nonisolated private static func mutatedDefinitionSnapshot(
        _ snapshot: PropertyDefinition,
        name: String?,
        state: PropertyDefinitionState,
        revision: Int64,
    ) -> PropertyDefinition {
        PropertyDefinition(
            id: snapshot.id,
            key: snapshot.key,
            name: name ?? snapshot.name,
            valueType: snapshot.valueType,
            cardinality: snapshot.cardinality,
            state: state,
            origin: snapshot.origin,
            revision: revision,
            options: snapshot.options,
            conditionCapability: snapshot.conditionCapability,
        )
    }

    nonisolated private static func optionCreateMatchesResponse(
        _ definition: PropertyDefinition,
        request: PropertyOptionCreateRequest,
    ) -> Bool {
        guard definitionMutationRevisionMatches(
            definition,
            propertyID: request.propertyID,
            expectedDefinitionRevision: request.expectedDefinitionRevision,
        ) else { return false }
        // CreateOption은 매번 새 UUID로 정확히 하나의 option을 마지막 ordinal
        // 뒤에 추가한다. 기존 option이 같은 label을 가질 수 있으므로, 사전
        // option snapshot과 대조해 정확히 하나의 새 마지막 option이 추가됐는지
        // 확인해야 누락·치환 응답이 거절된다.
        let options = definition.options.sorted(by: { $0.position < $1.position })
        guard options.dropLast() == request.expectedOptions,
              let created = options.last,
              created.id != request.expectedOptions.last?.id
        else { return false }
        return created.state == .active && created.label == request.label
    }

    nonisolated private static func optionUpdateMatchesResponse(
        _ definition: PropertyDefinition,
        request: PropertyOptionUpdateRequest,
    ) -> Bool {
        guard definitionMutationRevisionMatches(
            definition,
            propertyID: request.propertyID,
            expectedDefinitionRevision: request.expectedDefinitionRevision,
        ) else { return false }
        // RenameOption은 대상 label만 바꾼다. 다른 option의 변경·제거까지
        // 반영한 응답은 정상 daemon에서 생성될 수 없다.
        guard let expected = expectedOptionsAfterMutating(
            request.expectedOptions,
            optionID: request.optionID,
            transform: { option in
                PropertyOption(id: option.id, label: request.label, position: option.position, state: option.state)
            },
        ) else { return false }
        return definition.options == expected
    }

    nonisolated private static func optionReorderMatchesResponse(
        _ definition: PropertyDefinition,
        request: PropertyOptionReorderRequest,
    ) -> Bool {
        guard definitionMutationRevisionMatches(
            definition,
            propertyID: request.propertyID,
            expectedDefinitionRevision: request.expectedDefinitionRevision,
        ) else { return false }
        // ReorderOptions는 활성 option 순서만 바꾸고 label·state·identity는
        // 보존하며 ordinal을 재번호 매긴다. 다른 변경이 섞인 응답은 정상
        // daemon에서 생성될 수 없다.
        guard let expected = expectedOptionsAfterReorder(
            request.expectedOptions,
            optionIDs: request.optionIDs,
        ) else { return false }
        return definition.options == expected
    }

    nonisolated private static func optionDisableMatchesResponse(
        _ definition: PropertyDefinition,
        request: PropertyOptionDisableRequest,
    ) -> Bool {
        guard definitionMutationRevisionMatches(
            definition,
            propertyID: request.propertyID,
            expectedDefinitionRevision: request.expectedDefinitionRevision,
        ) else { return false }
        // DisableOption은 대상 상태만 비활성으로 바꾼다. 다른 option의
        // 변경·제거까지 반영한 응답은 정상 daemon에서 생성될 수 없다.
        guard let expected = expectedOptionsAfterMutating(
            request.expectedOptions,
            optionID: request.optionID,
            transform: { option in
                PropertyOption(id: option.id, label: option.label, position: option.position, state: .disabled)
            },
        ) else { return false }
        return definition.options == expected
    }

    /// 사전 option snapshot에서 대상 option 하나에만 transform을 적용한
    /// 기대 응답을 만든다. option 생성이 실패하면 검증 불가로 nil을 반환한다.
    nonisolated private static func expectedOptionsAfterMutating(
        _ expectedOptions: [PropertyOption],
        optionID: PropertyOptionID,
        transform: (PropertyOption) throws -> PropertyOption,
    ) -> [PropertyOption]? {
        var expected: [PropertyOption] = []
        expected.reserveCapacity(expectedOptions.count)
        for option in expectedOptions {
            do {
                try expected.append(option.id == optionID ? transform(option) : option)
            } catch {
                return nil
            }
        }
        return expected
    }

    /// 활성 option이 optionIDs 순서대로 오고 비활성 option이 snapshot 순서대로
    /// 뒤에 붙는 재번호된 기대 응답을 만든다. 요청이 활성 집합의 완전한 순열이
    /// 아니면 nil을 반환한다.
    nonisolated private static func expectedOptionsAfterReorder(
        _ expectedOptions: [PropertyOption],
        optionIDs: [PropertyOptionID],
    ) -> [PropertyOption]? {
        var activeByID: [PropertyOptionID: PropertyOption] = [:]
        var inactive: [PropertyOption] = []
        for option in expectedOptions {
            if option.state == .active {
                activeByID[option.id] = option
            } else {
                inactive.append(option)
            }
        }
        var expected: [PropertyOption] = []
        for id in optionIDs {
            guard let option = activeByID.removeValue(forKey: id) else { return nil }
            expected.append(option)
        }
        // 요청에 없는 활성 option이 남으면 완전한 순열이 아니다.
        guard activeByID.isEmpty else { return nil }
        expected.append(contentsOf: inactive)
        var renumbered: [PropertyOption] = []
        for (index, option) in expected.enumerated() {
            guard let renumberedOption = try? PropertyOption(
                id: option.id,
                label: option.label,
                position: index + 1,
                state: option.state,
            ) else { return nil }
            renumbered.append(renumberedOption)
        }
        return renumbered
    }

    nonisolated private static func definitionMutationRevisionMatches(
        _ definition: PropertyDefinition,
        propertyID: PropertyID,
        expectedDefinitionRevision: Int64,
        state: PropertyDefinitionState = .active,
    ) -> Bool {
        guard expectedDefinitionRevision >= 1, expectedDefinitionRevision < Int64.max,
              definition.origin == .userDefined
        else { return false }
        return definition.id == propertyID
            && definition.revision == expectedDefinitionRevision + 1
            && definition.state == state
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
        // assignment-list 경로는 단일 local-path target을 한 entry로 해석해
        // 조회한다. 서로 다른 entry의 값이 섞인 페이지는 생성 불가능한 응답이다.
        if let firstEntryID = page.assignments.first?.entryID,
           page.assignments.contains(where: { $0.entryID != firstEntryID })
        {
            return false
        }
        // ID 부분집합 검사 뒤에도 has_more 진행 검사를 계속 수행한다. 필터
        // 요청에서 조기 반환하면 반복 token이 승인될 수 있다.
        if !request.requestedPropertyIDs.isEmpty {
            let requested = Set(request.requestedPropertyIDs)
            guard page.assignments.allSatisfy({ requested.contains($0.propertyID) }) else {
                return false
            }
        }
        // has_more인 페이지는 page_size를 정확히 채우고 전진하는 token을 가져야
        // 한다(저장소가 limit+1행으로 판정한다). 같은 token의 반복은 페이지
        // 순회 caller를 끝내지 못하게 하므로 거절한다.
        guard page.hasMore else { return true }
        return page.assignments.count == request.pageSize
            && page.nextPageToken != nil
            && page.nextPageToken != request.pageToken
    }

    nonisolated private static func proposalOperation(
        _ requestID: @escaping @Sendable () -> String,
        _ makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
    ) -> @Sendable (EntryCoreEndpoint, PropertyChangeRequest) async throws -> PropertyChangeProposal {
        { endpoint, request in
            guard case let .proposal(value) = try await call(
                .propertyChangePrepare, endpoint, request, requestID, makeTransport,
            ) else { throw EntryCoreClientError.protocolMismatch }
            guard proposalMatchesRequest(value, request: request) else {
                throw EntryCoreClientError.protocolMismatch
            }
            return value
        }
    }

    nonisolated private static func proposalMatchesRequest(
        _ proposal: PropertyChangeProposal,
        request: PropertyChangeRequest,
    ) -> Bool {
        guard proposal.changes.count == request.changes.count else { return false }
        return zip(proposal.changes, request.changes).allSatisfy { prepared, requested in
            prepared.target == requested.target
                && (requested.entryID == nil || prepared.entryID == requested.entryID)
                && prepared.propertyID == requested.propertyID
                && prepared.after == requested.desired
                && preparedBeforeMatchesExpectedRevision(
                    prepared.before,
                    expectedAssignmentRevision: requested.expectedAssignmentRevision,
                    desired: requested.desired,
                )
        }
    }

    nonisolated private static func preparedBeforeMatchesExpectedRevision(
        _ before: PropertyAssignment?,
        expectedAssignmentRevision: Int64,
        desired: PropertyDesiredState,
    ) -> Bool {
        guard let before else { return expectedAssignmentRevision == 0 }
        guard expectedAssignmentRevision > 0, before.revision == expectedAssignmentRevision else {
            return false
        }
        // .value 변경의 before도 요청 contract와 같은 type·cardinality여야 한다.
        // 같은 revision이라도 다른 타입의 이전 값은 다른 CAS 기준이다.
        if case let .value(valueType, cardinality, _) = desired {
            return before.valueType == valueType && before.cardinality == cardinality
        }
        return true
    }

    nonisolated private static func executeOperation(
        _ requestID: @escaping @Sendable () -> String,
        _ makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
    ) -> @Sendable (EntryCoreEndpoint, PropertyChangeRequest) async throws -> [PropertyAssignment] {
        { endpoint, request in
            guard request.changes.allSatisfy({ $0.entryID != nil }) else {
                throw EntryCoreClientError.localValidation
            }
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
            executeAssignmentMatchesChange(assignment, change: change)
        }
    }

    nonisolated private static func executeAssignmentMatchesChange(
        _ assignment: PropertyAssignment,
        change: PropertyChangeTarget,
    ) -> Bool {
        // daemon 계약상 execute 응답 assignment는 요청 change로 완전히 결정된다:
        // revision은 expected + 1이고 state·payload는 desired를 그대로 반영한다.
        // identity만 비교하면 stale revision이나 다른 값의 응답도 승인되므로
        // 전부 대조해 protocolMismatch로 거절한다.
        guard let entryID = change.entryID,
              assignment.entryID == entryID,
              assignment.propertyID == change.propertyID,
              change.expectedAssignmentRevision >= 0,
              change.expectedAssignmentRevision < Int64.max,
              assignment.revision == change.expectedAssignmentRevision + 1
        else { return false }
        switch change.desired {
        case .null:
            return assignment.state == .null && assignment.value == nil
        case .unknown:
            return assignment.state == .unknown && assignment.value == nil
        case .notApplicable:
            return false
        case let .value(valueType, cardinality, value):
            return assignment.state == .value
                && assignment.valueType == valueType
                && assignment.cardinality == cardinality
                && assignment.value == value
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
        // daemon은 item 수가 정확히 pageSize에 도달한 뒤 candidate offset을 전진시킬
        // 때만 has_more을 설정한다(condition_query.go의 page completion 조건).
        // 꽉 차지 않은 페이지나 같은 token의 반복은 페이지 순회 caller를 끝내지
        // 못하게 하므로 거절한다.
        guard page.hasMore else { return true }
        return page.items.count == request.pageSize
            && page.nextPageToken != nil
            && page.nextPageToken != request.pageToken
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
