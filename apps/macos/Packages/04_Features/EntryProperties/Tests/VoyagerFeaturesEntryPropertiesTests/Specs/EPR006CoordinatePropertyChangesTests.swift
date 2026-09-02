import ComposableArchitecture
@testable import VoyagerFeaturesEntryProperties
import XCTest

@MainActor
final class EPR006CoordinatePropertyChangesTests: XCTestCase {
    // MARK: - EPR-006-discover_property_change_capabilities

    /// EPR-006-discover_property_change_capabilities: catalog-first 순서와 authoritative capability를 확인한다.
    /// 조건 조회 capability를 mutation capability로 승격하지 않는 경계를 검증한다.
    /// - 검증 내용: catalog → assignment → capability 호출 순서와 unknown 보존
    /// - 사전 조건: 하나의 고정 target selection과 unknown mutation capability
    /// - 기대 결과: snapshot이 게시되고 changeValue capability는 unknown으로 유지됨
    func testDiscoveryReadsCatalogBeforeAssignmentsAndPreservesUnknownMutationCapability() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        let unknownReport = EntryPropertiesCapabilityReport(
            items: [.init(operation: .changeValue, capability: .unknown)],
            supportsMultipleTargets: false,
            catalogVersion: "2.2.0",
        )
        let store = TestStore(initialState: EntryPropertiesState(selection: fixture.selection)) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = EntryPropertiesClient(
                loadCatalog: { _ in
                    await recorder.record("catalog")
                    return fixture.catalog
                },
                loadAssignments: { _, _ in
                    await recorder.record("assignments")
                    return fixture.assignments
                },
                discoverCapabilities: { _ in
                    await recorder.record("capabilities")
                    return unknownReport
                },
                prepare: { _ in throw EntryPropertiesFailure.unavailable },
                execute: { _ in throw EntryPropertiesFailure.unavailable },
                readBack: { _ in throw EntryPropertiesFailure.unavailable },
            )
        }

        await store.send(.discoverCapabilities) {
            $0.generation = 1
            $0.activePhase = .discovering
            $0.status = .discovering
        }
        let discovery = EntryPropertiesDiscovery(snapshot: fixture.snapshot, capabilities: unknownReport)
        await store.receive(.init(kind: .discoveryCompleted(1, .success(discovery)))) {
            $0.activePhase = nil
            $0.targetSnapshot = fixture.snapshot
            $0.capabilityReport = unknownReport
            $0.status = .ready
            $0.lastOutcome = .capabilitiesDiscovered(unknownReport)
        }
        await store.receive(.init(kind: .outcome(.capabilitiesDiscovered(unknownReport))))

        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["catalog", "assignments", "capabilities"])
        XCTAssertEqual(store.state.capabilityReport?.capability(for: .changeValue), .unknown)
    }

    /// EPR-006-discover_property_change_capabilities: unresolved selection은 fail closed한다.
    /// authoritative discovery 실패 시 지원 가능성을 추론하지 않는지 검증한다.
    /// - 검증 내용: unavailable 결과와 mutation capability 미게시
    /// - 사전 조건: catalog 조회가 실패하는 selection
    /// - 기대 결과: rejected(unavailable), capabilityReport=nil
    func testDiscoveryFailureDoesNotFabricateCapability() async {
        let fixture = Fixture()
        let store = TestStore(initialState: EntryPropertiesState(selection: fixture.selection)) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = .unavailable
        }

        await store.send(.discoverCapabilities) {
            $0.generation = 1
            $0.activePhase = .discovering
            $0.status = .discovering
        }
        await store.receive(.init(kind: .discoveryCompleted(1, .failure(.unavailable)))) {
            $0.activePhase = nil
            $0.status = .rejected(.unavailable)
            $0.lastOutcome = .propertyChangeRejected(.unavailable)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.unavailable))))
        XCTAssertNil(store.state.capabilityReport)
    }

    // MARK: - EPR-006-prepare_property_change

    /// EPR-006-prepare_property_change: 고정 snapshot과 before/after를 가진 immutable proposal을 준비한다.
    /// capability가 확인된 현재 revision에 대해서만 proposal을 게시하는지 검증한다.
    /// - 검증 내용: snapshot, differences, impact, validation, confirmation requirement
    /// - 사전 조건: changeValue 및 multi-target capability가 authoritative supported
    /// - 기대 결과: property_change_prepared outcome과 원본 snapshot 유지
    func testPreparePublishesImmutableProposalForCurrentSnapshot() async {
        let fixture = Fixture()
        var state = fixture.readyState
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(prepare: { _ in fixture.proposal })
        }

        await store.send(.prepare(fixture.intent)) {
            $0.activePhase = .preparing
            $0.status = .preparing
        }
        await store.receive(.init(kind: .prepareCompleted(0, .success(fixture.proposal)))) {
            $0.activePhase = nil
            $0.proposal = fixture.proposal
            $0.status = .prepared
            $0.lastOutcome = .propertyChangePrepared(fixture.proposal)
        }
        await store.receive(.init(kind: .outcome(.propertyChangePrepared(fixture.proposal))))
        state = store.state
        XCTAssertEqual(state.proposal?.snapshot, fixture.snapshot)
        XCTAssertEqual(state.proposal?.differences, fixture.proposal.differences)
    }

    /// EPR-006-prepare_property_change: 이전 generation의 completion은 현재 selection을 오염시키지 않는다.
    /// selection 교체 뒤 late proposal이 무시되는지 검증한다.
    /// - 검증 내용: generation freshness와 proposal publication 차단
    /// - 사전 조건: generation 0 prepare가 진행된 뒤 selection이 교체됨
    /// - 기대 결과: 이전 proposal은 게시되지 않고 새 selection이 유지됨
    func testLatePrepareCompletionCannotReplaceCurrentSelection() async {
        let fixture = Fixture()
        let replacement = EntryPropertiesSelection(
            targets: [.init(localPath: "/replacement")],
            propertyID: .init(rawValue: "property-b"),
        )
        var state = fixture.readyState
        state.generation = 1
        state.activePhase = .preparing
        state.status = .preparing
        let store = TestStore(initialState: state) { EntryPropertiesFeature() }

        await store.send(.selectionChanged(replacement)) {
            $0.generation = 2
            $0.selection = replacement
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.activePhase = nil
            $0.status = .idle
        }
        await store.send(.init(kind: .prepareCompleted(1, .success(fixture.proposal))))
        XCTAssertEqual(store.state.selection, replacement)
        XCTAssertNil(store.state.proposal)
    }

    // MARK: - EPR-006-execute_property_change

    /// EPR-006-execute_property_change: 확인이 필요한 proposal은 확인 전 로컬에서 거부한다.
    /// 정본 write dependency를 호출하지 않는 preflight를 검증한다.
    /// - 검증 내용: confirmationRequired outcome과 execute 호출 0회
    /// - 사전 조건: requiresConfirmation=true인 current proposal
    /// - 기대 결과: mutation 없이 property_change_rejected
    func testExecuteRejectsUnconfirmedProposalBeforeMutation() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.status = .prepared
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(execute: { proposal in
                await recorder.record("execute")
                return .init(snapshot: proposal.snapshot)
            })
        }

        await store.send(.execute(confirmed: false)) {
            $0.status = .rejected(.confirmationRequired)
            $0.lastOutcome = .propertyChangeRejected(.confirmationRequired)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.confirmationRequired))))
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, [])
    }

    /// EPR-006-execute_property_change: ambiguous completion은 mutation 재시도 없이 보존한다.
    /// 전송 또는 cancellation ambiguity를 성공·실패로 추정하지 않는지 검증한다.
    /// - 검증 내용: ambiguous status와 proposal 보존
    /// - 사전 조건: current proposal의 execute effect가 active
    /// - 기대 결과: 자동 execute/read-back 없이 ambiguous outcome
    func testAmbiguousExecutionIsNotRetried() async {
        let fixture = Fixture()
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.status = .executing
        state.activePhase = .executing
        let store = TestStore(initialState: state) { EntryPropertiesFeature() }

        await store.send(.init(kind: .executeCompleted(0, .failure(.ambiguousExecution)))) {
            $0.activePhase = nil
            $0.status = .ambiguous
            $0.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.ambiguousExecution))))
        XCTAssertEqual(store.state.proposal, fixture.proposal)
        XCTAssertNil(store.state.canonicalResult)
    }

    /// EPR-006-execute_property_change: trusted success 뒤 canonical read-back까지 완료한다.
    /// mutation과 정본 확인이 한 번씩 직렬 실행되는 happy path를 검증한다.
    /// - 검증 내용: applied → verified 전이와 execute/readBack 호출 횟수
    /// - 사전 조건: 확인된 current proposal과 authoritative supported capability
    /// - 기대 결과: 고정 snapshot의 canonical result가 property_change_verified로 게시됨
    func testTrustedExecuteReadsBackCanonicalResult() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.status = .prepared
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(
                execute: { proposal in
                    await recorder.record("execute")
                    return .init(snapshot: proposal.snapshot)
                },
                readBack: { _ in
                    await recorder.record("readBack")
                    return fixture.canonicalResult
                },
            )
        }

        await store.send(.execute(confirmed: true)) {
            $0.activePhase = .executing
            $0.status = .executing
        }
        await store.receive(.init(kind: .executeCompleted(0, .success(.init(snapshot: fixture.snapshot))))) {
            $0.activePhase = .applied
            $0.appliedProposal = fixture.proposal
            $0.status = .applied
            $0.lastOutcome = .propertyChangeApplied(fixture.snapshot)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeApplied(fixture.snapshot))))
        await store.receive(.init(kind: .readBackCompleted(0, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.canonicalResult = fixture.canonicalResult
            $0.status = .verified
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["execute", "readBack"])
    }

    // MARK: - EPR-006-read_back_property_change_result

    /// EPR-006-read_back_property_change_result: applied-unverified 재시도는 read-only다.
    /// mutation을 반복하지 않고 같은 고정 snapshot의 정본만 조회하는지 검증한다.
    /// - 검증 내용: readBack 1회, execute 0회, verified canonical result
    /// - 사전 조건: trusted apply 뒤 첫 정본 조회가 실패한 상태
    /// - 기대 결과: 동일 snapshot의 property_change_verified
    func testAppliedUnverifiedRetryPerformsReadBackOnly() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        var state = fixture.readyState
        state.status = .appliedUnverified
        state.appliedProposal = fixture.proposal
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(
                execute: { proposal in
                    await recorder.record("execute")
                    return .init(snapshot: proposal.snapshot)
                },
                readBack: { _ in
                    await recorder.record("readBack")
                    return fixture.canonicalResult
                },
            )
        }

        await store.send(.retryReadBack) {
            $0.activePhase = .applied
        }
        await store.receive(.init(kind: .readBackCompleted(0, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.canonicalResult = fixture.canonicalResult
            $0.status = .verified
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["readBack"])
    }

    /// EPR-006-read_back_property_change_result: lifecycle disposition matrix는 모든 조합을 소유한다.
    /// operation × phase × freshness × active effect × trust 누락을 구조적으로 검증한다.
    /// - 검증 내용: cartesian inventory 크기와 stale/ambiguous/read-only disposition
    /// - 사전 조건: 정의된 enum case inventory
    /// - 기대 결과: 모든 row가 정확히 한 disposition으로 분류됨
    func testLifecycleMatrixEnumeratesEveryDispositionCombination() {
        let expectedCount = EntryPropertiesOperationPhase.allCases.count
            * EntryPropertiesPhase.allCases.count
            * EntryPropertiesFreshness.allCases.count
            * EntryPropertiesActiveEffect.allCases.count
            * EntryPropertiesCompletionTrust.allCases.count
        XCTAssertEqual(EntryPropertiesLifecycleMatrix.allCases.count, expectedCount)
        XCTAssertEqual(Set(EntryPropertiesLifecycleMatrix.allCases).count, expectedCount)

        for lifecycleCase in EntryPropertiesLifecycleMatrix.allCases {
            let disposition = EntryPropertiesLifecycleMatrix.disposition(for: lifecycleCase)
            if lifecycleCase.freshness == .stale {
                XCTAssertEqual(disposition, .ignoreLate)
            }
            if lifecycleCase.operation == .execute,
               lifecycleCase.freshness == .current,
               lifecycleCase.activeEffect == .matching,
               lifecycleCase.trust == .ambiguous
            {
                XCTAssertEqual(disposition, .preserveAmbiguity)
            }
        }
    }
}

private struct Fixture {
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
