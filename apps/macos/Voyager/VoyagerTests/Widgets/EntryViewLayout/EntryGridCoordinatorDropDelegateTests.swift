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

    func testValidateDropOnPackageDirectoryStillTargetsFolder() throws {
        let package = makeFolderEntry(path: "/tmp/Test.app")
        let harness = makeHarness(
            entries: [package],
            currentPath: "/tmp",
            packagePaths: [package.fullPath],
        )
        let draggingInfo = try MockDraggingInfo(
            draggingLocation: harness.windowPoint(for: IndexPath(item: 0, section: 0)),
            draggingSourceOperationMask: [.copy],
            pasteboard: NSPasteboard(name: .drag),
        )

        let operation = harness.validateDrop(draggingInfo)

        XCTAssertEqual(operation, .copy)
        XCTAssertEqual(harness.store.state.entryOperations.dropValidationResult.destinationPath, package.fullPath)
        XCTAssertTrue(harness.store.state.isDropTargeted)
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, package.id)
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

    func testAcceptDropOnValidInternalFolderTargetRoutesHandleDrop() {
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

    func testAcceptDropOnValidExternalFolderTargetRoutesDropItems() {
        let folder = makeFolderEntry(path: "/tmp/target")
        let recorder = RouteRecorder()
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        pasteboard.writeObjects([NSURL(fileURLWithPath: "/tmp/external.txt")])
        let harness = makeHarness(entries: [folder], currentPath: "/tmp", recorder: recorder)
        let draggingInfo = MockDraggingInfo(
            draggingLocation: .zero,
            draggingSourceOperationMask: [.copy],
            pasteboard: pasteboard,
        )

        let accepted = harness.acceptDrop(draggingInfo)

        XCTAssertTrue(accepted)
        XCTAssertEqual(
            recorder.lastRoutingAction,
            .dropItems(sourcePaths: ["/tmp/external.txt"], destinationPath: folder.fullPath, isOptionDrag: true),
        )
    }

    func testAcceptDropOnPackageDirectoryRoutesHandleDrop() {
        let package = makeFolderEntry(path: "/tmp/Test.app")
        let recorder = RouteRecorder()
        let harness = makeHarness(
            entries: [package],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
            packagePaths: [package.fullPath],
            recorder: recorder,
        )
        let draggingInfo = MockDraggingInfo(
            draggingLocation: .zero,
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        )

        let accepted = harness.acceptDrop(draggingInfo)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.lastRoutingAction, .handleDrop(destinationPath: package.fullPath))
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
}

// MARK: - Harness

private typealias DepsConfig = (inout DependencyValues) -> Void

@MainActor
private func makeHarness(
    entries: [EntryModel],
    currentPath: String,
    internalDragPaths: [String] = [],
    packagePaths: Set<String> = [],
    recorder: RouteRecorder = RouteRecorder(),
) -> GridDropHarness {
    var state = EntryViewLayoutState()
    state.mode = .grid
    state.currentPath = currentPath
    state.entries = entries

    let deps: DepsConfig = {
        $0.entryLoadingClient = .testValue
        $0.entryLoadingClient.isPackageDirectory = { packagePaths.contains($0.path) }
        $0.entryFileOpsClient = .testValue
        $0.entryFileOpsClient.loadDragPaths = { internalDragPaths }
        $0.entryFileOpsClient.loadDragWithOption = { false }
        $0.workspaceClient = .testValue
        $0.finderFavoritesTagClient = .testValue
        $0.entryThumbnailCacheClient = .testValue
        $0.notificationCenterClient = .testValue
    }

    let store = Store(initialState: state) {
        Reduce<EntryViewLayoutState, EntryViewLayoutAction> { state, action in
            switch action {
            case let .view(.setDropTargeted(isTargeted)):
                state.isDropTargeted = isTargeted
                return .none
            case let .entryOperations(.routing(.handleDrop(_, destinationPath))):
                recorder.lastRoutingAction = .handleDrop(destinationPath: destinationPath)
                return .none
            case let .entryOperations(.routing(.dropItems(sourcePaths, destinationPath, isOptionDrag))):
                recorder.lastRoutingAction = .dropItems(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    isOptionDrag: isOptionDrag,
                )
                return .none
            default: return .none
            }
        }
        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsCommandRoutingReducer()
        }
    } withDependencies: { deps(&$0) }

    let (coordinator, view, window) = withDependencies(deps) {
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.contentView = view
        view.scrollView.frame = view.bounds
        view.collectionView.frame = NSRect(x: 0, y: 0, width: 640, height: 960)
        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        coordinator.rebuildSectionsAndReload()
        view.layoutSubtreeIfNeeded()
        return (coordinator, view, window)
    }

    return GridDropHarness(store: store, coordinator: coordinator, view: view, window: window, deps: deps)
}

@MainActor
private struct GridDropHarness {
    enum Region { case itemCenter, iconBackground }

    let store: Store<EntryViewLayoutState, EntryViewLayoutAction>
    let coordinator: EntryGridCoordinator
    let view: EntryGridView
    let window: NSWindow
    let deps: DepsConfig

    func withDeps<T>(_ body: @MainActor () throws -> T) rethrows -> T {
        try withDependencies(deps, operation: body)
    }

    func validateDrop(
        _ draggingInfo: NSDraggingInfo,
        indexPath: IndexPath = IndexPath(item: 0, section: 0),
    ) -> NSDragOperation {
        var proposed = indexPath as NSIndexPath
        var dropOp: NSCollectionView.DropOperation = .before
        return withDeps {
            withUnsafeMutablePointer(to: &proposed) { ptr in
                coordinator.collectionView(
                    coordinator.collectionView,
                    validateDrop: draggingInfo,
                    proposedIndexPath: AutoreleasingUnsafeMutablePointer(ptr),
                    dropOperation: &dropOp,
                )
            }
        }
    }

    func acceptDrop(
        _ draggingInfo: NSDraggingInfo,
        indexPath: IndexPath = IndexPath(item: 0, section: 0),
        dropOperation: NSCollectionView.DropOperation = .on,
    ) -> Bool {
        withDeps {
            coordinator.collectionView(
                coordinator.collectionView,
                acceptDrop: draggingInfo,
                indexPath: indexPath,
                dropOperation: dropOperation,
            )
        }
    }

    func windowPoint(for indexPath: IndexPath, region: Region = .itemCenter) throws -> NSPoint {
        view.layoutSubtreeIfNeeded()
        coordinator.collectionView.layoutSubtreeIfNeeded()
        guard let item = coordinator.collectionView.item(at: indexPath) else {
            throw NSError(domain: "EntryGridCoordinatorDropDelegateTests", code: 1)
        }
        let center: NSPoint
        switch region {
        case .itemCenter:
            center = NSPoint(x: item.view.frame.midX, y: item.view.frame.midY)
        case .iconBackground:
            guard let iconBg = findSubview(in: item.view, identifier: "entryGrid.iconBackground") else {
                throw NSError(domain: "EntryGridCoordinatorDropDelegateTests", code: 2)
            }
            let iconFrame = iconBg.convert(iconBg.bounds, to: coordinator.collectionView)
            center = NSPoint(x: iconFrame.midX, y: iconFrame.midY)
        }
        return coordinator.collectionView.convert(center, to: nil)
    }
}

// MARK: - Test Support

private final class RouteRecorder {
    var lastRoutingAction: RoutingAction?
}

private enum RoutingAction: Equatable {
    case handleDrop(destinationPath: String)
    case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
}

private func makeFolderEntry(path: String) -> EntryModel {
    let url = URL(fileURLWithPath: path)
    let epoch = Date(timeIntervalSince1970: 0)
    return EntryModel(
        name: url.lastPathComponent,
        fullPath: path,
        isFolder: true,
        isHidden: false,
        size: 0,
        modifiedDate: epoch,
        fileExtension: url.pathExtension,
        facets: EntryFacets(
            createdDate: epoch,
            addedDate: epoch,
            lastOpenedDate: nil,
            kind: "Folder",
            creatorApplication: nil,
            tags: [],
            supplementaryMetadata: nil,
        ),
    )
}

@MainActor
private func findSubview(in root: NSView, identifier: String) -> NSView? {
    if root.identifier?.rawValue == identifier { return root }
    for child in root.subviews {
        if let found = findSubview(in: child, identifier: identifier) { return found }
    }
    return nil
}

@MainActor
private final class MockDraggingInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    let draggingLocation: NSPoint
    let draggingPasteboard: NSPasteboard
    let draggingSource: Any?
    let draggingSequenceNumber: Int
    let draggingSourceOperationMask: NSDragOperation
    var draggedImageLocation: NSPoint
    var draggedImage: NSImage?
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var draggingFormation: NSDraggingFormation = .default
    var springLoadingHighlight: NSSpringLoadingHighlight = .none

    init(
        draggingLocation: NSPoint,
        draggingSourceOperationMask: NSDragOperation,
        pasteboard: NSPasteboard,
        draggingSource: Any? = nil,
    ) {
        self.draggingLocation = draggingLocation
        draggingPasteboard = pasteboard
        self.draggingSource = draggingSource
        draggingSequenceNumber = 1
        self.draggingSourceOperationMask = draggingSourceOperationMask
        draggedImageLocation = draggingLocation
        draggedImage = NSImage(size: NSSize(width: 1, height: 1))
        super.init()
    }

    func slideDraggedImage(to _: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination _: URL) -> [String]? { [] }
    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions,
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any],
        using _: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void,
    ) {}
    func resetSpringLoading() {}
}
