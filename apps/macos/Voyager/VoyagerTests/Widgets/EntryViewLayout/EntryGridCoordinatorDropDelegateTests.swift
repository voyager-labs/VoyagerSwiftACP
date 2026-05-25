import AppKit
import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

/// 드래그/드롭 경로와 시각 상태 회귀를 검증하는 테스트 모음이다.
@MainActor
final class EntryGridCoordinatorDropDelegateTests: XCTestCase {
    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testValidateDropOnFolderTileUsesFolderDestinationAndEnablesTargetState() throws {
        let folder = makeFolderEntry(path: "/tmp/target")
        let harness = makeHarness(entries: [folder], currentPath: "/tmp")
        let draggingInfo = try MockDraggingInfo(
            draggingLocation: harness.windowPoint(for: IndexPath(item: 0, section: 0)),
            draggingSourceOperationMask: [.copy],
            pasteboard: NSPasteboard(name: .drag),
        )

        let operation = harness.validateDrop(draggingInfo)

        XCTAssertEqual(operation, .copy)
        XCTAssertEqual(harness.store.state.entryOperations.dropValidationResult.destinationPath, folder.fullPath)
        XCTAssertTrue(harness.store.state.isDropTargeted)
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, folder.id)
    }

    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testValidateDropReturnsNoneForSameParentInternalMove() throws {
        let folder = makeFolderEntry(path: "/tmp/parent")
        let harness = makeHarness(
            entries: [folder],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/parent/source.txt"],
        )
        let draggingInfo = try MockDraggingInfo(
            draggingLocation: harness.windowPoint(for: IndexPath(item: 0, section: 0)),
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        )

        let operation = harness.validateDrop(draggingInfo)

        XCTAssertEqual(operation, [])
        XCTAssertEqual(harness.store.state.entryOperations.dropValidationResult.destinationPath, folder.fullPath)
        XCTAssertFalse(harness.store.state.isDropTargeted)
        XCTAssertNil(harness.coordinator.dropTargetEntryId)
    }

    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testValidateDropReturnsNoneForDescendantInternalMove() throws {
        let childFolder = makeFolderEntry(path: "/tmp/folder/child")
        let harness = makeHarness(
            entries: [childFolder],
            currentPath: "/tmp/folder",
            internalDragPaths: ["/tmp/folder"],
        )
        let draggingInfo = try MockDraggingInfo(
            draggingLocation: harness.windowPoint(for: IndexPath(item: 0, section: 0)),
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        )

        let operation = harness.validateDrop(draggingInfo)

        XCTAssertEqual(operation, [])
        XCTAssertEqual(harness.store.state.entryOperations.dropValidationResult.destinationPath, childFolder.fullPath)
        XCTAssertFalse(harness.store.state.isDropTargeted)
        XCTAssertNil(harness.coordinator.dropTargetEntryId)
    }

    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testAcceptDropOnValidInternalFolderTargetRoutesHandleDrop() throws {
        let folder = makeFolderEntry(path: "/tmp/target")
        let recorder = RouteRecorder()
        let harness = makeHarness(
            entries: [folder],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
            recorder: recorder,
        )
        let draggingInfo = try MockDraggingInfo(
            draggingLocation: harness.windowPoint(for: IndexPath(item: 0, section: 0)),
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        )

        _ = harness.validateDrop(draggingInfo)
        let accepted = harness.acceptDrop(draggingInfo)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.lastRoutingAction, .handleDrop(destinationPath: folder.fullPath))
    }

    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testAcceptDropUsesHoveredFolderTargetWhenAppKitReportsBeforeOperation() throws {
        let folder = makeFolderEntry(path: "/tmp/target")
        let recorder = RouteRecorder()
        let harness = makeHarness(
            entries: [folder],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
            recorder: recorder,
        )
        let draggingInfo = try MockDraggingInfo(
            draggingLocation: harness.windowPoint(for: IndexPath(item: 0, section: 0), region: .iconBackground),
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        )

        _ = harness.validateDrop(draggingInfo)
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, folder.id)

        let accepted = harness.acceptDrop(draggingInfo, dropOperation: .before)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.lastRoutingAction, .handleDrop(destinationPath: folder.fullPath))
    }

    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testAcceptDropOnValidExternalFolderTargetRoutesDropItems() throws {
        let folder = makeFolderEntry(path: "/tmp/target")
        let recorder = RouteRecorder()
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        pasteboard.writeObjects([NSURL(fileURLWithPath: "/tmp/external.txt")])
        let harness = makeHarness(entries: [folder], currentPath: "/tmp", recorder: recorder)
        let draggingInfo = try MockDraggingInfo(
            draggingLocation: harness.windowPoint(for: IndexPath(item: 0, section: 0)),
            draggingSourceOperationMask: [.copy],
            pasteboard: pasteboard,
        )

        _ = harness.validateDrop(draggingInfo)
        let accepted = harness.acceptDrop(draggingInfo)

        XCTAssertTrue(accepted)
        XCTAssertEqual(
            recorder.lastRoutingAction,
            .dropItems(sourcePaths: ["/tmp/external.txt"], destinationPath: folder.fullPath, isOptionDrag: true),
        )
    }

    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testAcceptDropOnPackageDirectoryRejectsDrop() throws {
        let package = makeFolderEntry(path: "/tmp/Test.app")
        let recorder = RouteRecorder()
        let harness = makeHarness(
            entries: [package],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
            packagePaths: [package.fullPath],
            recorder: recorder,
        )
        let draggingInfo = try MockDraggingInfo(
            draggingLocation: harness.windowPoint(for: IndexPath(item: 0, section: 0)),
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        )

        _ = harness.validateDrop(draggingInfo)
        let accepted = harness.acceptDrop(draggingInfo)

        XCTAssertFalse(accepted)
        XCTAssertNil(recorder.lastRoutingAction)
    }

    // MARK: - 버그 1: 성공적인 드롭 후 하이라이트가 유지되어야 함

    func testSuccessfulDropRetainsHighlightAfterAccept() {
        let folder = makeFolderEntry(path: "/tmp/target")
        let recorder = RouteRecorder()
        let harness = makeHarness(
            entries: [folder],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
            recorder: recorder,
        )
        let draggingInfo = MockDraggingInfo(
            draggingLocation: .zero,
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        )

        // validateDrop은 하이라이트 상태를 설정합니다(실제 AppKit 동작과 동일한 흐름).
        _ = harness.validateDrop(draggingInfo)
        XCTAssertTrue(harness.store.state.isDropTargeted, "validateDrop should enable drop targeting")
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, folder.id)

        // acceptDrop은 하이라이트를 유지해야 합니다(T2 수정).
        let accepted = harness.acceptDrop(draggingInfo)

        XCTAssertTrue(accepted, "Drop should be accepted on valid folder target")
        XCTAssertEqual(recorder.lastRoutingAction, .handleDrop(destinationPath: folder.fullPath))
        XCTAssertTrue(
            harness.store.state.isDropTargeted,
            "Highlight should persist after acceptDrop — clearing deferred to operation completion",
        )
        XCTAssertEqual(
            harness.coordinator.dropTargetEntryId,
            folder.id,
            "Drop target entry ID should persist after acceptDrop",
        )
    }

    // MARK: - 항목 대상 불변성: 하위 뷰 경계가 대상을 변경하지 않아야 함

    func testDropTargetIsInvariantAcrossEntrySubregions() throws {
        let folder = makeFolderEntry(path: "/tmp/target")
        let harness = makeHarness(
            entries: [folder],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
        )
        let indexPath = IndexPath(item: 0, section: 0)
        let itemCenterPoint = try harness.windowPoint(for: indexPath, region: .itemCenter)
        let iconBgPoint = try harness.windowPoint(for: indexPath, region: .iconBackground)
        let namePoint = try harness.windowPoint(for: indexPath, region: .nameArea)
        let thumbnailPoint = try harness.thumbnailImageWindowPoint(for: indexPath)

        for (label, point) in [
            ("itemCenter", itemCenterPoint),
            ("iconBackground", iconBgPoint),
            ("nameArea", namePoint),
            ("thumbnailImage", thumbnailPoint),
        ] {
            harness.coordinator.clearDropTargetState()
            let op = harness.validateDrop(MockDraggingInfo(
                draggingLocation: point,
                draggingSourceOperationMask: [.move],
                pasteboard: NSPasteboard(name: .drag),
            ))
            XCTAssertEqual(op, .move, "validateDrop from \(label) should return .move")
            XCTAssertEqual(
                harness.coordinator.dropTargetEntryId,
                folder.id,
                "Target from \(label) should be the folder entry",
            )
            XCTAssertEqual(
                harness.coordinator.validatedDropDestinationPath,
                folder.fullPath,
                "Destination from \(label) should be the folder path",
            )
        }
    }

    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testDropTargetStabilizesAcrossConsecutiveValidateCalls() throws {
        let folder = makeFolderEntry(path: "/tmp/target")
        let harness = makeHarness(
            entries: [folder],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
        )
        let indexPath = IndexPath(item: 0, section: 0)

        // 아이콘 배경에서 대상 설정
        let bgPoint = try harness.windowPoint(for: indexPath, region: .iconBackground)
        _ = harness.validateDrop(MockDraggingInfo(
            draggingLocation: bgPoint,
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        ))
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, folder.id)

        // 썸네일로 이동 — 같은 항목, 다른 하위 뷰 — 대상은 유지되어야 함
        let thumbPoint = try harness.thumbnailImageWindowPoint(for: indexPath)
        _ = harness.validateDrop(MockDraggingInfo(
            draggingLocation: thumbPoint,
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        ))
        XCTAssertEqual(
            harness.coordinator.dropTargetEntryId,
            folder.id,
            "Target should remain stable when moving from icon background to thumbnail",
        )

        // 이름 영역으로 이동 — 여전히 같은 항목
        let namePoint = try harness.windowPoint(for: indexPath, region: .nameArea)
        _ = harness.validateDrop(MockDraggingInfo(
            draggingLocation: namePoint,
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        ))
        XCTAssertEqual(
            harness.coordinator.dropTargetEntryId,
            folder.id,
            "Target should remain stable when moving from thumbnail to name area",
        )
    }

    /// 드래그/드롭 타겟 처리 회귀를 방지한다.
    func testDropTargetUpdatesWhenMovingToDifferentEntry() throws {
        let folder1 = makeFolderEntry(path: "/tmp/folder1")
        let folder2 = makeFolderEntry(path: "/tmp/folder2")
        let harness = makeHarness(
            entries: [folder1, folder2],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
        )

        let point1 = try harness.windowPoint(for: IndexPath(item: 0, section: 0))
        _ = harness.validateDrop(MockDraggingInfo(
            draggingLocation: point1,
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        ))
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, folder1.id)

        let point2 = try harness.windowPoint(for: IndexPath(item: 1, section: 0))
        _ = harness.validateDrop(MockDraggingInfo(
            draggingLocation: point2,
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        ))
        XCTAssertEqual(
            harness.coordinator.dropTargetEntryId,
            folder2.id,
            "Target should update when moving to a different entry tile",
        )
    }
}
