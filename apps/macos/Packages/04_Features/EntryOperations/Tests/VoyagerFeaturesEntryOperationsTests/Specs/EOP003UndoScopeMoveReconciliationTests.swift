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
