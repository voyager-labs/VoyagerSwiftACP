import AppKit
import Foundation
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EOP003UndoScopeMoveReconciliationTests: XCTestCase {
    /// EOP-003-undo_entry_action: canonical registry history는 legacy command facade에서도 한 번씩만 소비된다.
    /// 두 completion이 같은 native stack에 중복 등록되지 않고 최신 순서대로 연속 Undo되는지 검증한다.
    /// - 검증 내용: 두 Undo invocation과 event 순서, 최종 availability, native stack projection을 비교한다.
    /// - 사전 조건: 같은 scope에 A 다음 B record를 canonical registry로 등록하고 compatibility metadata를 연결한다.
    /// - 기대 결과: B 다음 A event가 방출되고 native Undo는 비며 두 record 모두 Redo 가능하다.
    func testLegacyFacadeConsumesCanonicalRegistryHistoryOncePerRecord() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let windowID = UUID()
        let ownerID = UUID()
        let scope = UndoManagerScope(windowID: windowID, contentTabID: "active")
        let manager = registry.activate(scope)
        let generation = try XCTUnwrap(registry.generation(for: scope))
        let firstRecord = EntryActionRecord(operationKind: .rename, targets: [])
        let secondRecord = EntryActionRecord(operationKind: .createFolder, targets: [])
        let client = UndoManagerClient.live(
            registry: registry,
            resolveScope: { requestedWindowID in
                requestedWindowID == windowID ? scope : nil
            },
        )
        var events = client.events(windowID).makeAsyncIterator()

        XCTAssertTrue(registry.registerUndo(scope, expectedGeneration: generation, record: firstRecord))
        await client.registerUndo(windowID, ownerID, firstRecord)
        XCTAssertTrue(registry.registerUndo(scope, expectedGeneration: generation, record: secondRecord))
        await client.registerUndo(windowID, ownerID, secondRecord)

        let secondIdentity = UndoManagerRecordIdentity(ownerID: ownerID, recordID: secondRecord.id)
        let firstUndo = await client.undo(windowID, expectedTarget: secondIdentity)
        let firstEvent = await events.next()
        let firstIdentity = UndoManagerRecordIdentity(ownerID: ownerID, recordID: firstRecord.id)
        let secondUndo = await client.undo(windowID, expectedTarget: firstIdentity)
        let secondEvent = await events.next()

        XCTAssertTrue(firstUndo.didInvoke)
        XCTAssertTrue(secondUndo.didInvoke)
        XCTAssertEqual(firstEvent, UndoManagerEvent(ownerID: ownerID, record: secondRecord, direction: .undo))
        XCTAssertEqual(secondEvent, UndoManagerEvent(ownerID: ownerID, record: firstRecord, direction: .undo))
        XCTAssertFalse(secondUndo.availability.canUndo)
        XCTAssertTrue(secondUndo.availability.canRedo)
        XCTAssertFalse(manager.canUndo)
        XCTAssertTrue(manager.canRedo)
        XCTAssertEqual(registry.generation(for: scope), generation)
    }

    /// EOP-003-undo_entry_action: delayed compatibility binding은 canonical history 순서를 바꾸지 않는다.
    /// A와 B가 먼저 canonical 등록된 뒤 A metadata가 늦게 도착해도 A를 native stack에 재등록하지 않는지 검증한다.
    /// - 검증 내용: delayed binding 뒤 Undo target과 두 event 순서, native stack 최종 상태를 비교한다.
    /// - 사전 조건: A canonical, B canonical 순으로 등록한 뒤 A, B compatibility metadata를 연결한다.
    /// - 기대 결과: B 다음 A가 한 번씩 Undo되고 추가 A action은 남지 않는다.
    func testDelayedCompatibilityBindingDoesNotDuplicateCanonicalRecord() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let windowID = UUID()
        let ownerID = UUID()
        let scope = UndoManagerScope(windowID: windowID, contentTabID: "active")
        let manager = registry.activate(scope)
        let generation = try XCTUnwrap(registry.generation(for: scope))
        let firstRecord = EntryActionRecord(operationKind: .rename, targets: [])
        let secondRecord = EntryActionRecord(operationKind: .createFolder, targets: [])
        let client = UndoManagerClient.live(registry: registry, resolveScope: { _ in scope })
        var events = client.events(windowID).makeAsyncIterator()

        XCTAssertTrue(registry.registerUndo(scope, expectedGeneration: generation, record: firstRecord))
        XCTAssertTrue(registry.registerUndo(scope, expectedGeneration: generation, record: secondRecord))
        await client.registerUndo(windowID, ownerID, firstRecord)
        await client.registerUndo(windowID, ownerID, secondRecord)

        let secondUndo = await client.undo(
            windowID,
            expectedTarget: .init(ownerID: ownerID, recordID: secondRecord.id),
        )
        let secondEvent = await events.next()
        let firstUndo = await client.undo(
            windowID,
            expectedTarget: .init(ownerID: ownerID, recordID: firstRecord.id),
        )
        let firstEvent = await events.next()

        XCTAssertTrue(secondUndo.didInvoke)
        XCTAssertTrue(firstUndo.didInvoke)
        XCTAssertEqual(secondEvent, .init(ownerID: ownerID, record: secondRecord, direction: .undo))
        XCTAssertEqual(firstEvent, .init(ownerID: ownerID, record: firstRecord, direction: .undo))
        XCTAssertFalse(firstUndo.availability.canUndo)
        XCTAssertFalse(manager.canUndo)
    }

    /// EOP-003-undo_entry_action: compatibility owner 무효화는 같은 scope의 다른 owner history를 보존한다.
    /// sidebar owner를 제거해도 content owner의 canonical/native Undo가 유지되는지 검증한다.
    /// - 검증 내용: owner invalidation 결과, 남은 target identity, unaffected owner Undo event를 비교한다.
    /// - 사전 조건: 같은 scope에 content owner A와 sidebar owner B record가 순서대로 등록된다.
    /// - 기대 결과: B만 제거되고 A가 다음 Undo target으로 남아 정상 replay된다.
    func testCompatibilityOwnerInvalidationPreservesOtherOwnerHistory() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let windowID = UUID()
        let contentOwnerID = UUID()
        let sidebarOwnerID = UUID()
        let scope = UndoManagerScope(windowID: windowID, contentTabID: "active")
        let manager = registry.activate(scope)
        let generation = try XCTUnwrap(registry.generation(for: scope))
        let contentRecord = EntryActionRecord(operationKind: .rename, targets: [])
        let sidebarRecord = EntryActionRecord(operationKind: .createFolder, targets: [])
        let client = UndoManagerClient.live(registry: registry, resolveScope: { _ in scope })
        var events = client.events(windowID).makeAsyncIterator()

        XCTAssertTrue(registry.registerUndo(scope, expectedGeneration: generation, record: contentRecord))
        await client.registerUndo(windowID, contentOwnerID, contentRecord)
        XCTAssertTrue(registry.registerUndo(scope, expectedGeneration: generation, record: sidebarRecord))
        await client.registerUndo(windowID, sidebarOwnerID, sidebarRecord)

        let invalidation = await client.invalidateOwner(windowID, sidebarOwnerID)
        let contentIdentity = UndoManagerRecordIdentity(ownerID: contentOwnerID, recordID: contentRecord.id)
        let undo = await client.undo(windowID, expectedTarget: contentIdentity)
        let event = undo.didInvoke ? await events.next() : nil

        XCTAssertTrue(invalidation.succeeded)
        XCTAssertEqual(invalidation.availability.undoTarget, contentIdentity)
        XCTAssertTrue(undo.didInvoke)
        XCTAssertEqual(event, .init(ownerID: contentOwnerID, record: contentRecord, direction: .undo))
        XCTAssertFalse(manager.canUndo)
        XCTAssertTrue(manager.canRedo)
        XCTAssertEqual(registry.generation(for: scope), generation)
    }

    /// EOP-003-undo_entry_action: owner 무효화 뒤 늦은 compatibility 등록은 history를 부활시키지 않는다.
    /// recovery가 폐기한 owner의 지연 completion을 tombstone으로 차단하는지 검증한다.
    /// - 검증 내용: invalidation 결과, late registration 결과, native availability를 비교한다.
    /// - 사전 조건: 활성 scope의 owner를 history 등록 전에 먼저 무효화한다.
    /// - 기대 결과: 같은 owner의 늦은 등록은 거부되고 native Undo history는 비어 있다.
    func testCompatibilityOwnerInvalidationRejectsDelayedRegistration() {
        let registry = FileOperationUndoManagerRegistry()
        let windowID = UUID()
        let ownerID = UUID()
        let scope = UndoManagerScope(windowID: windowID, contentTabID: "active")
        let manager = registry.activate(scope)
        let record = EntryActionRecord(operationKind: .rename, targets: [])

        let invalidation = registry.invalidateCompatibilityOwner(scope, ownerID: ownerID)
        let didRegister = registry.registerCompatibilityUndo(scope, ownerID: ownerID, record: record)

        XCTAssertTrue(invalidation.succeeded)
        XCTAssertFalse(didRegister)
        XCTAssertEqual(registry.compatibilityAvailability(scope), .init())
        XCTAssertFalse(manager.canUndo)
    }

    /// EOP-003-undo_entry_action: active scope가 사라진 owner 무효화도 늦은 compatibility 등록을 차단한다.
    /// close/recovery 사이 resolver가 nil인 구간에도 window-owner tombstone을 유지하는지 검증한다.
    /// - 검증 내용: nil-scope invalidation 결과와 이후 registration 결과를 비교한다.
    /// - 사전 조건: window와 owner는 알려져 있지만 invalidation 시점 active scope resolver는 nil이다.
    /// - 기대 결과: invalidation은 fail-closed 결과를 반환해도 같은 owner의 늦은 등록은 거부된다.
    func testCompatibilityOwnerInvalidationWithoutActiveScopeStillRejectsDelayedRegistration() {
        let registry = FileOperationUndoManagerRegistry()
        let windowID = UUID()
        let ownerID = UUID()
        let scope = UndoManagerScope(windowID: windowID, contentTabID: "closed")
        let manager = registry.activate(scope)
        let record = EntryActionRecord(operationKind: .rename, targets: [])

        let invalidation = registry.invalidateCompatibilityOwner(nil, ownerID: ownerID, windowID: windowID)
        let didRegister = registry.registerCompatibilityUndo(scope, ownerID: ownerID, record: record)

        XCTAssertFalse(invalidation.succeeded)
        XCTAssertFalse(didRegister)
        XCTAssertFalse(manager.canUndo)
    }

    /// EOP-003-undo_entry_action: window 무효화 뒤 늦은 compatibility 등록과 새 event stream은 닫힌다.
    /// close가 끝난 window lifecycle을 지연 completion과 재구독이 다시 열지 못하는지 검증한다.
    /// - 검증 내용: late registration 결과, native availability, post-close stream 종료를 비교한다.
    /// - 사전 조건: 활성 scope가 있는 window를 먼저 무효화한 뒤 등록과 stream 생성을 시도한다.
    /// - 기대 결과: 등록은 거부되고 native history는 비며 새 stream은 즉시 종료된다.
    func testCompatibilityWindowInvalidationRejectsDelayedRegistrationAndClosesNewStreams() async {
        let registry = FileOperationUndoManagerRegistry()
        let windowID = UUID()
        let ownerID = UUID()
        let scope = UndoManagerScope(windowID: windowID, contentTabID: "active")
        let manager = registry.activate(scope)
        let record = EntryActionRecord(operationKind: .rename, targets: [])

        let invalidation = registry.invalidateCompatibilityWindow(windowID)
        let didRegister = registry.registerCompatibilityUndo(scope, ownerID: ownerID, record: record)
        let streamFinished = expectation(description: "post-close stream finishes")
        let streamTask = Task {
            var events = registry.compatibilityEvents(windowID: windowID).makeAsyncIterator()
            if await events.next() == nil {
                streamFinished.fulfill()
            }
        }

        await fulfillment(of: [streamFinished], timeout: 0.2)
        streamTask.cancel()
        XCTAssertTrue(invalidation.succeeded)
        XCTAssertFalse(didRegister)
        XCTAssertEqual(registry.compatibilityAvailability(scope), .init())
        XCTAssertFalse(manager.canUndo)
    }

    /// EOP-003-undo_entry_action: compatibility metadata는 callback 시점 active tab이 아니라 canonical origin scope를 따른다.
    /// A completion 뒤 active resolver가 B를 반환해도 동일 record를 B에 재등록하지 않는지 검증한다.
    /// - 검증 내용: A와 B scope의 availability와 native history를 비교한다.
    /// - 사전 조건: A scope에 canonical record가 있고 compatibility client resolver는 B를 반환한다.
    /// - 기대 결과: A만 owner/record target을 노출하고 B native history는 비어 있다.
    func testCompatibilityRegistrationFindsCanonicalOriginScopeAfterActiveTabSwitch() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let windowID = UUID()
        let ownerID = UUID()
        let scopeA = UndoManagerScope(windowID: windowID, contentTabID: "A")
        let scopeB = UndoManagerScope(windowID: windowID, contentTabID: "B")
        let managerA = registry.activate(scopeA)
        let managerB = registry.activate(scopeB)
        let generationA = try XCTUnwrap(registry.generation(for: scopeA))
        let record = EntryActionRecord(operationKind: .rename, targets: [])
        let client = UndoManagerClient.live(registry: registry, resolveScope: { _ in scopeB })

        XCTAssertTrue(registry.registerUndo(scopeA, expectedGeneration: generationA, record: record))
        await client.registerUndo(windowID, ownerID, record)

        let identity = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
        XCTAssertEqual(registry.compatibilityAvailability(scopeA).undoTarget, identity)
        XCTAssertEqual(registry.compatibilityAvailability(scopeB), .init())
        XCTAssertTrue(managerA.canUndo)
        XCTAssertFalse(managerB.canUndo)
    }

    /// EOP-003-undo_entry_action: compatibility metadata는 cross-window 이동 뒤 canonical record의 현재 scope를 따른다.
    /// 지연 등록이 과거 source window를 기준으로 새 history를 만들지 않고 moved entry에 결합되는지 검증한다.
    /// - 검증 내용: 이동 뒤 registration 결과, source/target availability, native Undo event를 비교한다.
    /// - 사전 조건: source scope에 canonical record를 등록하고 target window scope로 이동한 뒤 source resolver로 등록한다.
    /// - 기대 결과: target만 owner/record target을 노출하고 동일 native history가 한 번 Undo된다.
    func testCompatibilityRegistrationFindsCanonicalScopeAfterCrossWindowMove() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let sourceWindowID = UUID()
        let targetWindowID = UUID()
        let ownerID = UUID()
        let source = UndoManagerScope(windowID: sourceWindowID, contentTabID: "moved")
        let target = UndoManagerScope(windowID: targetWindowID, contentTabID: "moved")
        let manager = registry.activate(source)
        let generation = try XCTUnwrap(registry.generation(for: source))
        let record = EntryActionRecord(operationKind: .rename, targets: [])
        var events = registry.compatibilityEvents(windowID: targetWindowID).makeAsyncIterator()

        XCTAssertTrue(registry.registerUndo(source, expectedGeneration: generation, record: record))
        XCTAssertEqual(
            registry.moveScopes([.init(source: source, target: target)]),
            .moved,
        )
        let didRegister = registry.registerCompatibilityUndo(source, ownerID: ownerID, record: record)
        let identity = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
        let undo = registry.performCompatibilityUndoRedo(
            target,
            expectedTarget: identity,
            direction: .undo,
        )
        let event = undo.didInvoke ? await events.next() : nil

        XCTAssertTrue(didRegister)
        XCTAssertEqual(registry.compatibilityAvailability(source), .init())
        XCTAssertEqual(undo.availability.redoTarget, identity)
        XCTAssertEqual(event, .init(ownerID: ownerID, record: record, direction: .undo))
        XCTAssertFalse(manager.canUndo)
        XCTAssertTrue(manager.canRedo)
        XCTAssertEqual(registry.generation(for: target), generation)
    }

    /// EOP-003-undo_entry_action: 역방향 scope 이동 실패 뒤 동일 generation의 moved history를 source로 복원한다.
    /// durable Content Tab 이동 실패가 target에 남은 native history를 원래 scope로 되돌리는지 검증한다.
    /// - 검증 내용: reconciliation outcome, manager identity, generation, source scope의 Undo 성공을 비교한다.
    /// - 사전 조건: source history가 target으로 이동했고 receipt가 현재 target generation을 가리킨다.
    /// - 기대 결과: target이 제거되고 동일 manager와 history가 source scope에서 다시 동작한다.
    func testReconcileFailedScopeMoveRestoresMatchingTargetHistory() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let source = UndoManagerScope(windowID: UUID(), contentTabID: "source")
        let target = UndoManagerScope(windowID: UUID(), contentTabID: "target")
        let descriptor = FileOperationUndoScopeMoveDescriptor(source: source, target: target)
        let record = EntryActionRecord(operationKind: .rename, targets: [])
        let manager = try XCTUnwrap(client.activate(source))
        let generation = try XCTUnwrap(client.generation(source))
        XCTAssertTrue(client.registerUndo(source, generation, record))
        XCTAssertEqual(client.moveScopes([descriptor]), .moved)
        let targetGeneration = try XCTUnwrap(client.generation(target))

        let outcome = client.reconcileFailedScopeMove(
            [.init(descriptor: descriptor, targetGeneration: targetGeneration)],
            .targetOccupied(source),
        )

        let restoredSourceManager = await client.undoManager(source)
        let removedTargetManager = await client.undoManager(target)
        XCTAssertEqual(outcome, .restored)
        XCTAssertIdentical(manager, restoredSourceManager)
        XCTAssertNil(removedTargetManager)
        XCTAssertEqual(client.generation(source), generation)
        XCTAssertEqual(client.performUndoRedo(source, generation, .undo, record.id), .applied)
    }

    /// EOP-003-undo_entry_action: source가 재점유되면 moved history를 격리하고 terminal history loss를 반환한다.
    /// 역방향 이동의 targetOccupied 실패가 새 source history를 덮어쓰거나 이동된 history를 노출하지 않는지 검증한다.
    /// - 검증 내용: historyLost outcome, source identity/history 보존, target history 제거를 비교한다.
    /// - 사전 조건: 기존 source history가 target으로 이동한 뒤 source에 별도 history가 새로 생성된다.
    /// - 기대 결과: 새 source manager와 Undo는 보존되고 matching target manager의 history는 제거된다.
    func testReconcileFailedScopeMoveQuarantinesHistoryWhenSourceIsOccupied() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let source = UndoManagerScope(windowID: UUID(), contentTabID: "source")
        let target = UndoManagerScope(windowID: UUID(), contentTabID: "target")
        let descriptor = FileOperationUndoScopeMoveDescriptor(source: source, target: target)
        let movedRecord = EntryActionRecord(operationKind: .rename, targets: [])
        let replacementRecord = EntryActionRecord(operationKind: .createFolder, targets: [])
        let movedManager = try XCTUnwrap(client.activate(source))
        let movedGeneration = try XCTUnwrap(client.generation(source))
        XCTAssertTrue(client.registerUndo(source, movedGeneration, movedRecord))
        XCTAssertEqual(client.moveScopes([descriptor]), .moved)
        let targetGeneration = try XCTUnwrap(client.generation(target))
        let replacementManager = try XCTUnwrap(client.activate(source))
        let replacementGeneration = try XCTUnwrap(client.generation(source))
        XCTAssertTrue(client.registerUndo(source, replacementGeneration, replacementRecord))
        let reverseOutcome = FileOperationUndoScopesMoveOutcome.targetOccupied(source)

        let outcome = client.reconcileFailedScopeMove(
            [.init(descriptor: descriptor, targetGeneration: targetGeneration)],
            reverseOutcome,
        )

        let preservedSourceManager = await client.undoManager(source)
        let removedTargetManager = await client.undoManager(target)
        XCTAssertEqual(outcome, .historyLost(reverseOutcome))
        XCTAssertIdentical(replacementManager, preservedSourceManager)
        XCTAssertNil(removedTargetManager)
        XCTAssertFalse(movedManager.canUndo)
        XCTAssertFalse(movedManager.canRedo)
        XCTAssertEqual(client.generation(source), replacementGeneration)
        XCTAssertEqual(
            client.performUndoRedo(source, replacementGeneration, .undo, replacementRecord.id),
            .applied,
        )
    }
}
