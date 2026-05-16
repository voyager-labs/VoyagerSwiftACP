import AppKit
import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerFeaturesEntryOperations
import VoyagerFeaturesEntryThumbnail
import VoyagerShared
import XCTest

@MainActor
final class EntryGridThumbnailDropTargetTests: XCTestCase {
    func testValidateDropOnThumbnailImageCenterResolvesFolderDestination() throws {
        let folder = makeThumbnailDropFolderEntry(path: "/tmp/target")
        let harness = makeThumbnailDropHarness(
            entries: [folder],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
        )
        let draggingInfo = try MockThumbnailDraggingInfo(
            draggingLocation: harness.thumbnailImageWindowPoint(for: IndexPath(item: 0, section: 0)),
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        )

        let operation = harness.validateDrop(draggingInfo)

        XCTAssertEqual(operation, .move)
        XCTAssertEqual(
            harness.store.state.entryOperations.dropValidationResult.destinationPath,
            folder.fullPath,
        )
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, folder.id)
    }

    func testValidateDropOnPackageDirectoryThumbnailResolvesDestination() throws {
        let package = makeThumbnailDropFolderEntry(path: "/tmp/Test.app")
        let harness = makeThumbnailDropHarness(
            entries: [package],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
        )
        let draggingInfo = try MockThumbnailDraggingInfo(
            draggingLocation: harness.thumbnailImageWindowPoint(for: IndexPath(item: 0, section: 0)),
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        )

        let operation = harness.validateDrop(draggingInfo)

        XCTAssertEqual(operation, .move)
        XCTAssertEqual(
            harness.store.state.entryOperations.dropValidationResult.destinationPath,
            package.fullPath,
        )
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, package.id)
    }

    func testAcceptDropOnThumbnailImageCenterRoutesHandleDrop() throws {
        let folder = makeThumbnailDropFolderEntry(path: "/tmp/target")
        let recorder = ThumbnailDropRouteRecorder()
        let harness = makeThumbnailDropHarness(
            entries: [folder],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
            recorder: recorder,
        )
        let draggingInfo = try MockThumbnailDraggingInfo(
            draggingLocation: harness.thumbnailImageWindowPoint(for: IndexPath(item: 0, section: 0)),
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        )

        _ = harness.validateDrop(draggingInfo)
        let accepted = harness.acceptDrop(draggingInfo)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.lastRoutingAction, .handleDrop(destinationPath: folder.fullPath))
    }

    func testThumbnailToItemCenterStabilizesEntryTarget() throws {
        let folder = makeThumbnailDropFolderEntry(path: "/tmp/target")
        let harness = makeThumbnailDropHarness(
            entries: [folder],
            currentPath: "/tmp",
            internalDragPaths: ["/tmp/source.txt"],
        )
        let indexPath = IndexPath(item: 0, section: 0)

        let bgPoint = try harness.iconBackgroundWindowPoint(for: indexPath)
        _ = harness.validateDrop(MockThumbnailDraggingInfo(
            draggingLocation: bgPoint,
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        ))
        XCTAssertEqual(harness.coordinator.dropTargetEntryId, folder.id)

        let thumbPoint = try harness.thumbnailImageWindowPoint(for: indexPath)
        let op = harness.validateDrop(MockThumbnailDraggingInfo(
            draggingLocation: thumbPoint,
            draggingSourceOperationMask: [.move],
            pasteboard: NSPasteboard(name: .drag),
        ))
        XCTAssertEqual(op, .move)
        XCTAssertEqual(
            harness.coordinator.dropTargetEntryId,
            folder.id,
        )
        XCTAssertEqual(harness.coordinator.validatedDropDestinationPath, folder.fullPath)
    }
}

private typealias ThumbnailDepsConfig = (inout DependencyValues) -> Void

@MainActor
private func makeThumbnailDropHarness(
    entries: [EntryModel],
    currentPath: String,
    internalDragPaths: [String] = [],
    recorder: ThumbnailDropRouteRecorder = ThumbnailDropRouteRecorder(),
) -> ThumbnailDropHarness {
    var state = EntryViewLayoutState()
    state.mode = .grid
    state.currentPath = currentPath
    state.entries = entries

    let deps: ThumbnailDepsConfig = {
        $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
        $0.entryFileOpsClient = VoyagerFeaturesEntryOperations.EntryFileOpsClient.testValue
        $0.entryFileOpsClient.loadDragPaths = { internalDragPaths }
        $0.entryFileOpsClient.loadDragWithOption = { false }
        $0.workspaceClient = VoyagerShared.WorkspaceClient.testValue
        $0.finderFavoritesTagClient = Voyager.FinderFavoritesTagClient.testValue
        $0.entryThumbnailCacheClient = VoyagerEntitiesEntry.EntryThumbnailCacheClient.testValue
        $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
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
            default: return .none
            }
        }
        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsCommandRoutingReducer()
        }
    } withDependencies: { deps(&$0) }

    let ctx = withDependencies(deps) {
        makeThumbnailDropUI(store: store)
    }

    return ThumbnailDropHarness(
        store: store,
        coordinator: ctx.coordinator,
        view: ctx.view,
        window: ctx.window,
        deps: deps,
    )
}

private struct ThumbnailDropUIContext {
    let coordinator: EntryGridCoordinator
    let view: EntryGridView
    let window: NSWindow
}

@MainActor
private func makeThumbnailDropUI(store: Store<EntryViewLayoutState, EntryViewLayoutAction>) -> ThumbnailDropUIContext {
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
    return ThumbnailDropUIContext(coordinator: coordinator, view: view, window: window)
}

@MainActor
private struct ThumbnailDropHarness {
    let store: Store<EntryViewLayoutState, EntryViewLayoutAction>
    let coordinator: EntryGridCoordinator
    let view: EntryGridView
    let window: NSWindow
    let deps: ThumbnailDepsConfig

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

    func thumbnailImageWindowPoint(for indexPath: IndexPath) throws -> NSPoint {
        view.layoutSubtreeIfNeeded()
        coordinator.collectionView.layoutSubtreeIfNeeded()
        guard let item = coordinator.collectionView.item(at: indexPath),
              let iconBg = findThumbnailSubview(in: item.view, identifier: "entryGrid.iconBackground"),
              let imageView = iconBg.subviews.first(where: { $0 is NSImageView })
        else {
            throw NSError(domain: "EntryGridThumbnailDropTargetTests", code: 1)
        }
        let imageFrame = imageView.convert(imageView.bounds, to: coordinator.collectionView)
        let center = NSPoint(x: imageFrame.midX, y: imageFrame.midY)
        return coordinator.collectionView.convert(center, to: nil)
    }

    func iconBackgroundWindowPoint(for indexPath: IndexPath) throws -> NSPoint {
        view.layoutSubtreeIfNeeded()
        coordinator.collectionView.layoutSubtreeIfNeeded()
        guard let item = coordinator.collectionView.item(at: indexPath),
              let iconBg = findThumbnailSubview(in: item.view, identifier: "entryGrid.iconBackground")
        else {
            throw NSError(domain: "EntryGridThumbnailDropTargetTests", code: 2)
        }
        let bgFrame = iconBg.convert(iconBg.bounds, to: coordinator.collectionView)
        let center = NSPoint(x: bgFrame.midX, y: bgFrame.midY)
        return coordinator.collectionView.convert(center, to: nil)
    }
}

private final class ThumbnailDropRouteRecorder {
    var lastRoutingAction: ThumbnailDropRoutingAction?
}

private enum ThumbnailDropRoutingAction: Equatable {
    case handleDrop(destinationPath: String)
}

private func makeThumbnailDropFolderEntry(path: String) -> EntryModel {
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
private func findThumbnailSubview(in root: NSView, identifier: String) -> NSView? {
    if root.identifier?.rawValue == identifier { return root }
    for child in root.subviews {
        if let found = findThumbnailSubview(in: child, identifier: identifier) { return found }
    }
    return nil
}

@MainActor
private final class MockThumbnailDraggingInfo: NSObject, NSDraggingInfo {
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
