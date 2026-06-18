@_spi(Internals) import ComposableArchitecture
import Foundation
@testable import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class RCL005EditCollectionConditionsTests: XCTestCase {
    // MARK: - RCL-005-add_collection_condition

    /// RCL-005-add_collection_condition: 완성된 condition은 저장 가능한 filter 정의가 됨
    /// 값이 모두 채워진 condition이 save snapshot으로 변환되는지 검증한다.
    /// - 검증 내용: saveRequested 후 pending snapshot에 encoded condition이 포함되는지 확인
    /// - 사전 조건: `kind equals pdf` condition을 가진 collection context
    /// - 기대 결과: save가 시작되고 pending snapshot condition 값이 `.string("pdf")`로 저장됨
    func testSaveRequested_withCompleteCondition_preparesPendingSnapshot() async {
        let payload = makePayload(conditions: [makeCompleteKindCondition()])
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionSavePanelClient.defaultSaveDirectory = { _ in nil }
            $0.collectionSavePanelClient.presentSavePanel = { _ in nil }
        }

        await store.send(.saveRequested(payload)) {
            $0.isSaving = true
            $0.pendingSaveContext = payload.context
            $0.pendingSave = CollectionSaveSnapshot(
                query: "invoice",
                scopes: ["/VoyagerFixtures/Documents"],
                excludedScopes: [],
                includeSubfolders: true,
                includeDirectories: false,
                conditions: [
                    CollectionCondition(propertyKey: "kind", operatorCode: "eq", value: .string("pdf")),
                ],
                snapshotItems: nil,
                definitionFingerprint: "condition-fingerprint",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                relevanceRoots: ["/VoyagerFixtures/Documents"],
            )
        }
        await store.receive(\.savePanelResponse) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }
    }

    /// RCL-005-add_collection_condition: inactive placeholder condition은 저장 snapshot에서 제외된다.
    /// 새 조건 row가 아직 활성화되지 않았을 때 저장 가능한 filter 정의에 포함되지 않는지 검증한다.
    /// - 검증 내용: inactive condition filtering과 pending save condition count
    /// - 사전 조건: active condition 1개와 inactive placeholder condition 1개가 공존함
    /// - 기대 결과: pending snapshot에는 active condition만 포함됨
    func testSaveRequested_withInactivePlaceholderCondition_excludesPlaceholderFromSnapshot() async {
        let payload = makePayload(conditions: [makeCompleteKindCondition(), makeInactivePlaceholderCondition()])
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionSavePanelClient.defaultSaveDirectory = { _ in nil }
            $0.collectionSavePanelClient.presentSavePanel = { _ in nil }
        }

        await store.send(.saveRequested(payload)) {
            $0.isSaving = true
            $0.pendingSaveContext = payload.context
            $0.pendingSave = self.makeExpectedSnapshot(conditions: [
                CollectionCondition(propertyKey: "kind", operatorCode: "eq", value: .string("pdf")),
            ])
        }
        await store.receive(\.savePanelResponse) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }
    }

    // MARK: - RCL-005-change_collection_condition_property

    /// RCL-005-change_collection_condition_property: property가 바뀐 condition은 새 property key로 저장된다.
    /// condition property 선택 결과가 저장 snapshot의 `propertyKey`에 반영되는지 검증한다.
    /// - 검증 내용: pending save snapshot의 propertyKey와 encoded value
    /// - 사전 조건: `Name` property condition에 `contains report` 값이 입력됨
    /// - 기대 결과: snapshot condition은 `name` property와 `.string("report")` 값을 가짐
    func testSaveRequested_withChangedPropertyCondition_persistsNewPropertyKey() async {
        let payload = makePayload(conditions: [makeNameContainsCondition()])
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionSavePanelClient.defaultSaveDirectory = { _ in nil }
            $0.collectionSavePanelClient.presentSavePanel = { _ in nil }
        }

        await store.send(.saveRequested(payload)) {
            $0.isSaving = true
            $0.pendingSaveContext = payload.context
            $0.pendingSave = self.makeExpectedSnapshot(conditions: [
                CollectionCondition(propertyKey: "name", operatorCode: "contains", value: .string("report")),
            ])
        }
        await store.receive(\.savePanelResponse) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }
    }

    // MARK: - RCL-005-change_collection_condition_operator

    /// RCL-005-change_collection_condition_operator: 값이 필요 없는 operator는 nil value condition으로 저장된다.
    /// operator 변경 결과가 arity 0 계약을 따르는지 검증한다.
    /// - 검증 내용: operatorCode와 nil encoded value
    /// - 사전 조건: `Has Tags` 조건이 값 없는 operator로 구성됨
    /// - 기대 결과: snapshot condition은 `operatorCode`만 가지고 value는 nil임
    func testSaveRequested_withZeroArityOperator_persistsNilConditionValue() async {
        let payload = makePayload(conditions: [makeHasTagCondition()])
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionSavePanelClient.defaultSaveDirectory = { _ in nil }
            $0.collectionSavePanelClient.presentSavePanel = { _ in nil }
        }

        await store.send(.saveRequested(payload)) {
            $0.isSaving = true
            $0.pendingSaveContext = payload.context
            $0.pendingSave = self.makeExpectedSnapshot(conditions: [
                CollectionCondition(propertyKey: "tag", operatorCode: "exists", value: nil),
            ])
        }
        await store.receive(\.savePanelResponse) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }
    }

    // MARK: - RCL-005-delete_collection_condition

    /// RCL-005-delete_collection_condition: 삭제된 condition은 저장 snapshot에 남지 않는다.
    /// 현재 context에서 제거된 condition 목록만 저장 파이프라인에 전달되는지 검증한다.
    /// - 검증 내용: deleted condition 부재와 남은 condition 보존
    /// - 사전 조건: 삭제 후 남은 `kind equals pdf` condition만 payload에 포함됨
    /// - 기대 결과: pending snapshot에는 삭제된 `name` condition 없이 kind condition만 저장됨
    func testSaveRequested_afterConditionDeletion_persistsRemainingConditionsOnly() async {
        let payload = makePayload(conditions: [makeCompleteKindCondition()])
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionSavePanelClient.defaultSaveDirectory = { _ in nil }
            $0.collectionSavePanelClient.presentSavePanel = { _ in nil }
        }

        await store.send(.saveRequested(payload)) {
            $0.isSaving = true
            $0.pendingSaveContext = payload.context
            $0.pendingSave = self.makeExpectedSnapshot(conditions: [
                CollectionCondition(propertyKey: "kind", operatorCode: "eq", value: .string("pdf")),
            ])
        }
        await store.receive(\.savePanelResponse) {
            $0.isSaving = false
            $0.pendingSave = nil
            $0.pendingSaveContext = nil
        }
    }

    // MARK: - RCL-005-change_collection_condition_value

    /// RCL-005-change_collection_condition_value: 값이 비어 있는 condition은 saveBlocked feedback을 냄
    /// operator가 값을 요구하지만 입력값이 없으면 저장이 시작되지 않아야 한다.
    /// - 검증 내용: incomplete condition feedback category와 propertyLabel 확인
    /// - 사전 조건: `Kind` condition의 operator는 선택됐지만 values가 비어 있음
    /// - 기대 결과: pending save 없이 `.saveBlocked/.incompleteCondition` feedback이 전달됨
    func testSaveRequested_withMissingConditionValue_emitsIncompleteConditionFeedback() async throws {
        let payload = makePayload(conditions: [makeMissingValueCondition()])
        var state = CollectionState()

        let actions = await reduce(&state, action: .saveRequested(payload))

        XCTAssertFalse(state.isSaving)
        XCTAssertNil(state.pendingSave)
        let feedback = try XCTUnwrap(saveFeedback(from: actions))
        XCTAssertEqual(feedback.stage, .saveBlocked)
        XCTAssertEqual(feedback.category, .incompleteCondition)
        XCTAssertEqual(feedback.message, "Complete the filter for \"Kind\" before saving.")
        XCTAssertEqual(feedback.propertyLabel, "Kind")
        XCTAssertFalse(feedback.isRetryable)
    }

    /// RCL-005-change_collection_condition_value: 잘못된 condition 값은 invalid feedback을 냄
    /// 날짜 range 입력에 relative literal이 섞이면 값 변환 실패로 저장이 차단되어야 한다.
    /// - 검증 내용: invalid condition feedback category와 propertyLabel 확인
    /// - 사전 조건: `Modified` range date condition에 relative literal과 absolute date가 함께 입력됨
    /// - 기대 결과: `.saveBlocked/.invalidConditionValue` feedback이 전달됨
    func testSaveRequested_withInvalidConditionValue_emitsInvalidConditionFeedback() async throws {
        let payload = makePayload(conditions: [makeInvalidDateRangeCondition()])
        var state = CollectionState()

        let actions = await reduce(&state, action: .saveRequested(payload))

        XCTAssertFalse(state.isSaving)
        XCTAssertNil(state.pendingSave)
        let feedback = try XCTUnwrap(saveFeedback(from: actions))
        XCTAssertEqual(feedback.stage, .saveBlocked)
        XCTAssertEqual(feedback.category, .invalidConditionValue)
        XCTAssertEqual(feedback.message, "Check the value for \"Modified\" before saving.")
        XCTAssertEqual(feedback.propertyLabel, "Modified")
        XCTAssertFalse(feedback.isRetryable)
    }

    /// RCL-005-change_collection_condition_value: registry의 today operator는 값 없는 date operator로 정의됨
    /// 조건 편집 UI가 today preset을 값 입력 없이 사용할 수 있도록 registry metadata가 유지되는지 검증한다.
    /// - 검증 내용: `today` operator의 value shape/count와 date UI kind
    /// - 사전 조건: root shared registry fixture를 decode함
    /// - 기대 결과: today operator는 `.none`, fixed 0, date UI kind `none`으로 정의됨
    func testChangeConditionValue_registryIncludesTodayAsZeroArityDateOperator() throws {
        let registry = try loadConditionRegistry()
        let today = try XCTUnwrap(registry.operators["today"])

        XCTAssertEqual(today.valueShape, ValueShape.none)
        XCTAssertEqual(today.valueCount, .fixed(0))
        XCTAssertEqual(today.allowedTypes, ["date"])
        XCTAssertEqual(today.uiValueKind?["date"], "none")
    }

    /// RCL-005-change_collection_condition_value: canonical relative date literal은 single date condition 값으로 보존됨
    /// 날짜 condition 값 정규화가 relative literal을 손상시키지 않는지 검증한다.
    /// - 검증 내용: singleDate normalize 결과와 reset index
    /// - 사전 조건: relative date literal 앞뒤에 공백이 포함됨
    /// - 기대 결과: canonical literal만 trim되어 보존되고 오류가 없음
    func testChangeConditionValue_withRelativeSingleDate_preservesCanonicalLiteral() {
        let result = ValueNormalizerUtils.normalize(
            kind: "singleDate",
            rawValues: ["  \(relativeDateLiteral)  "],
            editingIndex: nil,
        )

        XCTAssertEqual(result.values, [relativeDateLiteral])
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.resetIndices, [])
    }

    /// RCL-005-change_collection_condition_value: today offset literal은 single date condition 값으로 보존됨
    /// recents/today 계열 condition literal이 값 정규화에서 유지되는지 검증한다.
    /// - 검증 내용: today offset literal normalize 결과
    /// - 사전 조건: recents opened literal 값이 입력됨
    /// - 기대 결과: literal이 유지되고 오류가 없음
    func testChangeConditionValue_withTodayOffsetLiteral_preservesLiteral() {
        let result = ValueNormalizerUtils.normalize(
            kind: "singleDate",
            rawValues: ["  \(todayOffsetLiteral)  "],
            editingIndex: nil,
        )

        XCTAssertEqual(result.values, [todayOffsetLiteral])
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.resetIndices, [])
    }

    /// RCL-005-change_collection_condition_value: range date에는 relative literal을 저장하지 않음
    /// range date condition 값에 relative literal이 섞이면 invalid value로 분류되는지 검증한다.
    /// - 검증 내용: rangeDate normalize error와 reset index
    /// - 사전 조건: range 시작값이 relative literal이고 종료값은 absolute date임
    /// - 기대 결과: values는 nil이고 첫 번째 입력 index가 reset 대상이 됨
    func testChangeConditionValue_withRelativeRangeDate_rejectsInvalidLiteral() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeDate",
            rawValues: [relativeDateLiteral, "2025-05-20"],
            editingIndex: nil,
        )

        XCTAssertNil(result.values)
        XCTAssertEqual(result.errorMessage, "Enter valid dates.")
        XCTAssertEqual(result.resetIndices, [0])
    }

    /// RCL-005-change_collection_condition_value: single date condition encoding은 relative literal을 보존함
    /// save pipeline이 사용하는 encoder가 single date literal을 JSON string으로 보존하는지 검증한다.
    /// - 검증 내용: ConditionValueEncoder singleDate output
    /// - 사전 조건: operator `eq`와 singleDate UI kind가 지정됨
    /// - 기대 결과: encoded value가 relative literal string임
    func testChangeConditionValue_withRelativeSingleDate_encodesAsString() {
        let encoded = ConditionValueEncoder.encodeValues(
            values: [relativeDateLiteral],
            valueType: "date",
            operatorCode: "eq",
            operatorValueUIKind: "singleDate",
        )

        XCTAssertEqual(encoded, .string(relativeDateLiteral))
    }

    /// RCL-005-change_collection_condition_value: range date condition encoding은 absolute date만 canonicalize함
    /// range date 값 저장 시 absolute date가 canonical ISO 값으로 변환되는지 검증한다.
    /// - 검증 내용: rangeDate encoder array output
    /// - 사전 조건: start/end absolute timestamp가 입력됨
    /// - 기대 결과: encoded value는 canonical date string 배열임
    func testChangeConditionValue_withAbsoluteRangeDate_encodesCanonicalArray() throws {
        let start = "2025-05-17T12:00:00Z"
        let end = "2025-05-20T23:59:59Z"
        let encoded = ConditionValueEncoder.encodeValues(
            values: [start, end],
            valueType: "date",
            operatorCode: "btw",
            operatorValueUIKind: "rangeDate",
        )

        let canonicalStart = try XCTUnwrap(ValueNormalizerUtils.canonicalAbsoluteDateString(start))
        let canonicalEnd = try XCTUnwrap(ValueNormalizerUtils.canonicalAbsoluteDateString(end))
        XCTAssertEqual(encoded, .array([.string(canonicalStart), .string(canonicalEnd)]))
    }

    /// RCL-005-change_collection_condition_value: range date encoder는 relative literal을 저장하지 않음
    /// 저장 직전 encoder가 invalid range date 입력을 nil로 반환하는지 검증한다.
    /// - 검증 내용: invalid rangeDate encoder output
    /// - 사전 조건: relative literal과 absolute date가 range 값으로 함께 전달됨
    /// - 기대 결과: encoded value가 nil임
    func testChangeConditionValue_withRelativeRangeDate_encoderReturnsNil() {
        let encoded = ConditionValueEncoder.encodeValues(
            values: [relativeDateLiteral, "2025-05-20"],
            valueType: "date",
            operatorCode: "btw",
            operatorValueUIKind: "rangeDate",
        )

        XCTAssertNil(encoded)
    }

    private let relativeDateLiteral = "voyager.relativeDate:v1:past:3:day:2025-05-17"
    private let todayOffsetLiteral = AppliedFilterValueUtils.recentsSinceAnyOpenedLiteral

    private func loadConditionRegistry() throws -> PropertyConditionRegistry {
        let root = try repositoryRoot()
        let url = root.appendingPathComponent("shared/property_condition_registry.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PropertyConditionRegistry.self, from: data)
    }

    private func repositoryRoot() throws -> URL {
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while current.path != "/" {
            if FileManager.default
                .fileExists(atPath: current.appendingPathComponent("shared/property_condition_registry.json").path)
            {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw NSError(domain: "RCL005EditCollectionConditionsTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "repository root with shared/property_condition_registry.json not found",
        ])
    }

    private func reduce(
        _ state: inout CollectionState,
        action: CollectionAction,
    ) async -> [CollectionAction] {
        let effect = CollectionFeature().reduce(into: &state, action: action)
        var actions: [CollectionAction] = []
        for await action in effect.actions {
            actions.append(action)
        }
        return actions
    }

    private func saveFeedback(from actions: [CollectionAction]) -> CollectionSaveFeedback? {
        for action in actions {
            if case let .delegate(.saveFeedback(feedback)) = action {
                return feedback
            }
        }
        return nil
    }

    private func makePayload(conditions: [Condition]) -> SaveRequestPayload {
        SaveRequestPayload(
            context: CollectionContext(
                query: "invoice",
                scopes: ["/VoyagerFixtures/Documents"],
                excludedScopes: [],
                includeSubfolders: true,
                includeDirectories: false,
                conditions: conditions,
            ),
            isSearchLoading: false,
            isFiltersLoading: false,
            snapshotItems: nil,
            definitionFingerprint: "condition-fingerprint",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            relevanceRoots: ["/VoyagerFixtures/Documents"],
            openedCompatibility: nil,
        )
    }

    private func makeCompleteKindCondition() -> Condition {
        Condition(
            propertyKey: "kind",
            propertyLabel: "Kind",
            propertyType: "text",
            operatorCode: "eq",
            operatorLabel: "is",
            operatorValueArity: 1,
            operatorValueUIKind: "text",
            valueType: "text",
            values: ["pdf"],
        )
    }

    private func makeExpectedSnapshot(conditions: [CollectionCondition]) -> CollectionSaveSnapshot {
        CollectionSaveSnapshot(
            query: "invoice",
            scopes: ["/VoyagerFixtures/Documents"],
            excludedScopes: [],
            includeSubfolders: true,
            includeDirectories: false,
            conditions: conditions,
            snapshotItems: nil,
            definitionFingerprint: "condition-fingerprint",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            relevanceRoots: ["/VoyagerFixtures/Documents"],
        )
    }

    private func makeInactivePlaceholderCondition() -> Condition {
        Condition(
            propertyKey: "placeholder",
            propertyLabel: "Placeholder",
            propertyType: "text",
            operatorCode: nil,
            operatorLabel: nil,
            operatorValueArity: nil,
            operatorValueUIKind: nil,
            valueType: "text",
            values: nil,
            isActive: false,
        )
    }

    private func makeNameContainsCondition() -> Condition {
        Condition(
            propertyKey: "name",
            propertyLabel: "Name",
            propertyType: "text",
            operatorCode: "contains",
            operatorLabel: "contains",
            operatorValueArity: 1,
            operatorValueUIKind: "text",
            valueType: "text",
            values: ["report"],
        )
    }

    private func makeHasTagCondition() -> Condition {
        Condition(
            propertyKey: "tag",
            propertyLabel: "Tag",
            propertyType: "tag",
            operatorCode: "exists",
            operatorLabel: "has any tag",
            operatorValueArity: 0,
            operatorValueUIKind: "none",
            valueType: "none",
            values: nil,
        )
    }

    private func makeMissingValueCondition() -> Condition {
        Condition(
            propertyKey: "kind",
            propertyLabel: "Kind",
            propertyType: "text",
            operatorCode: "eq",
            operatorLabel: "is",
            operatorValueArity: 1,
            operatorValueUIKind: "text",
            valueType: "text",
            values: [],
        )
    }

    private func makeInvalidDateRangeCondition() -> Condition {
        Condition(
            propertyKey: "modifiedDate",
            propertyLabel: "Modified",
            propertyType: "date",
            operatorCode: "btw",
            operatorLabel: "between",
            operatorValueArity: 2,
            operatorValueUIKind: "rangeDate",
            valueType: "date",
            values: [
                "voyager.relativeDate:v1:past:3:day:2025-05-17",
                "2025-05-20",
            ],
        )
    }
}
