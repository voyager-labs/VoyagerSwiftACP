import ComposableArchitecture
@testable import VoyagerEntryCoreClient
@testable import VoyagerFeaturesEntryProperties
import XCTest

/// 단일 필터 페이지네이션 계약: daemon은 ID·target 필터를 페이징 전에 적용하므로
/// 단일 ID·target(pageSize 256) 요청의 정상 응답은 한 페이지다. hasMore는 wire
/// 계약 위반으로 거절해 무한 transport 루프를 막는다.
extension EPR006CoordinatePropertyChangesTests {
    /// EPR-006-discover_property_change_capabilities: catalog 로드는 두 번째 페이지를 받지 않는다.
    /// - 검증 내용: hasMore 응답의 protocolMismatch 거절과 transport 호출 1회 종료
    /// - 사전 조건: 빈 definition 페이지에 hasMore를 반환하는 Core stub
    /// - 기대 결과: capability discovery가 토큰 추적 없이 즉시 실패로 종료됨
    func testLoadCatalogRejectsSecondPageUnderSingleIDFilter() async throws {
        let recorder = OperationRecorder()
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let propertyClient = paginatingPropertyClient(
            definitionList: { _, _ in
                await recorder.record("definitionList")
                return PropertyDefinitionPage(definitions: [], nextPageToken: "token", hasMore: true)
            },
            assignmentList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        )
        let client = try EntryPropertiesClientFactory.live(
            propertyClient: propertyClient,
            endpoint: EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock"),
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let selection = EntryPropertiesSelection(
            targets: [.init(localPath: "/a")],
            propertyID: .init(rawValue: propertyID.rawValue),
        )

        do {
            _ = try await client.loadCatalog(selection)
            XCTFail("second page under single-ID filter should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["definitionList"])
    }

    /// EPR-006-discover_property_change_capabilities: assignment 로드는 두 번째 페이지를 받지 않는다.
    /// - 검증 내용: 단일 target × ID 요청의 hasMore 거절과 transport 호출 1회 종료
    /// - 사전 조건: 빈 assignment 페이지에 hasMore를 반환하는 Core stub
    /// - 기대 결과: assignment 로드가 토큰 추적 없이 즉시 실패로 종료됨
    func testLoadAssignmentsRejectsSecondPageUnderSingleTargetFilter() async throws {
        let recorder = OperationRecorder()
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let propertyClient = paginatingPropertyClient(
            definitionList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
            assignmentList: { _, _ in
                await recorder.record("assignmentList")
                return PropertyAssignmentPage(assignments: [], nextPageToken: "token", hasMore: true)
            },
        )
        let client = try EntryPropertiesClientFactory.live(
            propertyClient: propertyClient,
            endpoint: EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock"),
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let selection = EntryPropertiesSelection(
            targets: [.init(localPath: "/a")],
            propertyID: .init(rawValue: propertyID.rawValue),
        )
        let catalog = EntryPropertiesCatalog(version: "2.2.0")

        do {
            _ = try await client.loadAssignments(selection, catalog)
            XCTFail("second page under single-target filter should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["assignmentList"])
    }

    /// EPR-006-discover_property_change_capabilities: discovery 조립의 전송 전
    /// 실패는 caller 입력 결함이므로 validation으로 분류된다.
    /// - 검증 내용: malformed property ID·local path의 .validation 변환
    /// - 사전 조건: wire 생성자가 거절하는 공개 selection 값
    /// - 기대 결과: unavailable(복구 대상) 대신 validation(caller 결함)으로 fail closed
    func testDiscoveryClassifiesMalformedSelectionAsValidation() async throws {
        let propertyClient = paginatingPropertyClient(
            definitionList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
            assignmentList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        )
        let client = try EntryPropertiesClientFactory.live(
            propertyClient: propertyClient,
            endpoint: EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock"),
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let catalog = EntryPropertiesCatalog(version: "2.2.0")

        let badIDSelection = EntryPropertiesSelection(
            targets: [.init(localPath: "/a")],
            propertyID: .init(rawValue: "not-a-uuid"),
        )
        do {
            _ = try await client.loadCatalog(badIDSelection)
            XCTFail("malformed property ID should be rejected as validation")
        } catch {
            XCTAssertEqual(error as? EntryPropertiesFailure, .validation)
        }

        let badPathSelection = EntryPropertiesSelection(
            targets: [.init(localPath: "")],
            propertyID: .init(rawValue: "00000000-0000-0000-8000-000000000001"),
        )
        do {
            _ = try await client.loadAssignments(badPathSelection, catalog)
            XCTFail("malformed local path should be rejected as validation")
        } catch {
            XCTAssertEqual(error as? EntryPropertiesFailure, .validation)
        }
    }

    /// EPR-006-discover_property_change_capabilities: catalog과 capability의
    /// catalog version이 모두 있으면 일치해야 한다.
    /// - 검증 내용: version 불일치의 stale discovery 실패
    /// - 사전 조건: catalog 2.2.0에 3.0.0 capability를 반환하는 provider
    /// - 기대 결과: 서로 다른 계약을 한 snapshot으로 묶지 않고 discovery 실패
    func testDiscoveryRejectsCapabilityCatalogVersionMismatch() async {
        let client = EntryPropertiesClient(
            loadCatalog: { _ in EntryPropertiesCatalog(version: "2.2.0") },
            loadAssignments: { selection, _ in
                EntryPropertiesAssignments(
                    canonicalRevision: 0,
                    values: selection.targets.map { .init(target: $0, value: .unset, revision: 0) },
                )
            },
            discoverCapabilities: { _ in
                EntryPropertiesCapabilityReport(
                    items: [.init(operation: .changeValue, capability: .supported)],
                    supportsMultipleTargets: true,
                    catalogVersion: "3.0.0",
                )
            },
            prepare: { _ in throw EntryPropertiesFailure.unavailable },
            execute: { _ in throw EntryPropertiesFailure.unavailable },
            readBack: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let fixture = Fixture()
        let store = TestStore(initialState: fixture.readyState) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = client
        }

        await store.send(.discoverCapabilities) {
            $0.generation = 1
            $0.activePhase = .discovering
            $0.status = .discovering
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.proposal = nil
            $0.canonicalResult = nil
        }
        await store.receive(.init(kind: .discoveryCompleted(1, .failure(.stale)))) {
            $0.activePhase = nil
            $0.status = .rejected(.stale)
            $0.lastOutcome = .propertyChangeRejected(.stale)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.stale))))
    }
}

private func paginatingPropertyClient(
    definitionList: @escaping @Sendable (EntryCoreEndpoint, PropertyDefinitionListRequest) async throws
        -> PropertyDefinitionPage,
    assignmentList: @escaping @Sendable (EntryCoreEndpoint, PropertyAssignmentListRequest) async throws
        -> PropertyAssignmentPage,
) -> EntryCorePropertyClient {
    EntryCorePropertyClient(
        definitionList: definitionList,
        definitionCreate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        definitionUpdate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        definitionDisable: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionCreate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionUpdate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionReorder: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionDisable: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        assignmentList: assignmentList,
        changePrepare: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        changeExecute: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        conditionQuery: { _, _ in throw EntryCoreClientError.daemonUnavailable },
    )
}
