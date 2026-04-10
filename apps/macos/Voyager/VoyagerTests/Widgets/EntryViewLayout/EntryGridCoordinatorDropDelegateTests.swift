import AppKit
import ComposableArchitecture
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class EntryGridCoordinatorDropDelegateTests: XCTestCase {
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

    // MARK: - Bug 1: Successful drop should retain highlight after accept

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

        // validateDrop sets up highlight state (mirrors real AppKit flow)
        _ = harness.validateDrop(draggingInfo)
        XCTAssertTrue(harness.store.state.isDropTargeted, "validateDrop should enable drop targeting")
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, folder.id)

        // acceptDrop should retain highlight (T2 fix)
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

    // MARK: - Entry-target invariance: subview boundaries must not change the target

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

    func testDropTargetStabilizesAcrossConsecutiveValidateCalls() throws {
        let folder = makeFolderEntry(path: "/tmp/target")
        let harness = makeHarness(
            entries: [folder],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
        )
        let indexPath = IndexPath(item: 0, section: 0)

        // Establish target from icon background
        let bgPoint = try harness.windowPoint(for: indexPath, region: .iconBackground)
        _ = harness.validateDrop(MockDraggingInfo(
            draggingLocation: bgPoint,
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        ))
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, folder.id)

        // Move to thumbnail — same entry, different subview — target must remain
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

        // Move to name area — still same entry
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
