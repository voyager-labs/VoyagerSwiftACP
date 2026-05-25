import AppKit
import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared

typealias DepsConfig = (inout DependencyValues) -> Void

@MainActor
func makeHarness(
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
        $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
        $0[VoyagerEntitiesEntry.EntryLoadingClient.self].isPackageDirectory = { packagePaths.contains($0.path) }
        $0.entryFileOpsClient = VoyagerFeaturesEntryOperations.EntryFileOpsClient.testValue
        $0.entryFileOpsClient.loadDragPaths = { internalDragPaths }
        $0.entryFileOpsClient.loadDragWithOption = { false }
        $0.workspaceClient = VoyagerShared.WorkspaceClient.testValue
        $0.finderFavoritesTagClient = .testValue
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

    let ctx = withDependencies(deps) {
        makeBoundGridUI(store: store)
    }

    return GridDropHarness(store: store, coordinator: ctx.coordinator, view: ctx.view, window: ctx.window, deps: deps)
}

struct GridUIContext {
    let coordinator: EntryGridCoordinator
    let view: EntryGridView
    let window: NSWindow
}

@MainActor
func makeBoundGridUI(store: Store<EntryViewLayoutState, EntryViewLayoutAction>) -> GridUIContext {
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
    return GridUIContext(coordinator: coordinator, view: view, window: window)
}

@MainActor
struct GridDropHarness {
    enum Region { case itemCenter, iconBackground, nameArea }

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
        case .nameArea:
            guard let nameContainer = findSubview(in: item.view, identifier: "entryGrid.nameContainer") else {
                throw NSError(domain: "EntryGridCoordinatorDropDelegateTests", code: 4)
            }
            let nameFrame = nameContainer.convert(nameContainer.bounds, to: coordinator.collectionView)
            center = NSPoint(x: nameFrame.midX, y: nameFrame.midY)
        }
        return coordinator.collectionView.convert(center, to: nil)
    }

    func thumbnailImageWindowPoint(for indexPath: IndexPath) throws -> NSPoint {
        view.layoutSubtreeIfNeeded()
        coordinator.collectionView.layoutSubtreeIfNeeded()
        guard let item = coordinator.collectionView.item(at: indexPath),
              let iconBg = findSubview(in: item.view, identifier: "entryGrid.iconBackground"),
              let imageView = iconBg.subviews.first(where: { $0 is NSImageView })
        else {
            throw NSError(domain: "EntryGridCoordinatorDropDelegateTests", code: 3)
        }
        let imageFrame = imageView.convert(imageView.bounds, to: coordinator.collectionView)
        let center = NSPoint(x: imageFrame.midX, y: imageFrame.midY)
        return coordinator.collectionView.convert(center, to: nil)
    }
}

final class RouteRecorder {
    var lastRoutingAction: RoutingAction?
}

enum RoutingAction: Equatable {
    case handleDrop(destinationPath: String)
    case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
}

func makeFolderEntry(path: String) -> EntryModel {
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
func findSubview(in root: NSView, identifier: String) -> NSView? {
    if root.identifier?.rawValue == identifier { return root }
    for child in root.subviews {
        if let found = findSubview(in: child, identifier: identifier) { return found }
    }
    return nil
}

@MainActor
final class MockDraggingInfo: NSObject, NSDraggingInfo {
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
