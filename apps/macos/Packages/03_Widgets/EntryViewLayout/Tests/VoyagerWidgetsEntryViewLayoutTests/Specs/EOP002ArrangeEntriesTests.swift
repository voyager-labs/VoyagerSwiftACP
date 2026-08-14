import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesEntryOperations
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

/// acceptDrop이 emit하는 source/destination/operation을 관찰하기 위한 기록 모델.
private struct EmittedDrop: Equatable {
    var sourcePaths: [String]
    var destinationPath: String
    var isOptionDrag: Bool
}

private final class DropRecorder {
    var emitted: [EmittedDrop] = []
}

private struct DropRecordingReducer: Reducer {
    typealias State = EntryViewLayoutState
    typealias Action = EntryViewLayoutAction

    let recorder: DropRecorder
    var inner: EntryViewLayoutFeature

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        if case let .delegate(.dropItems(sourcePaths, destinationPath, isOptionDrag)) = action {
            recorder.emitted.append(EmittedDrop(
                sourcePaths: sourcePaths,
                destinationPath: destinationPath,
                isOptionDrag: isOptionDrag,
            ))
        }
        return inner.reduce(into: &state, action: action)
    }
}

/// `saveDragPaths`/`loadDragPaths`/`loadDragWithOption`가 공유하는 가변 transport 상태.
private final class DragTransport: @unchecked Sendable {
    var paths: [String]
    var option: Bool

    init(paths: [String] = [], option: Bool = false) {
        self.paths = paths
        self.option = option
    }
}

@MainActor
final class EOP002ArrangeEntriesTests: XCTestCase {
    // MARK: - EOP-002-drop_external_entries_on_directory_page (origin classification)

    /// EOP-002: foreign `draggingSource`(layout source가 아님) + stale transport + external pasteboard → external URL만
    /// emit한다.
    func testExternalDropEmitsOnlyActiveExternalURLWithStaleTransport() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let recorder = DropRecorder()
        let externalURL = URL(fileURLWithPath: "/external/file.txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])

        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(
            source: NSObject(),
            operationMask: [.copy, .move],
            pasteboard: pasteboard,
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, [externalURL.path])
        XCTAssertEqual(recorder.emitted.first?.destinationPath, "/destination")
    }

    /// EOP-002 (FIX 1 core regression): `draggingSource == nil` + stale transport + external pasteboard
    /// → stored path를 신뢰하지 않고 active external pasteboard만 source로 사용한다 (Grid).
    func testNilSourceExternalDropIgnoresStaleTransport() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let recorder = DropRecorder()
        let externalURL = URL(fileURLWithPath: "/external/url.txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])

        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, [externalURL.path])
        XCTAssertFalse(recorder.emitted.first?.sourcePaths.contains("/stale/internal") ?? true)
    }

    /// EOP-002 (FIX 1 core regression): `draggingSource == nil` + stale transport + external pasteboard
    /// → stored path를 신뢰하지 않고 active external pasteboard만 source로 사용한다 (List).
    func testNilSourceExternalDropIgnoresStaleTransportList() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let recorder = DropRecorder()
        let externalURL = URL(fileURLWithPath: "/external/list-url.txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])

        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current")
        let list = EntryListCoordinator(store: store)

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveListAccept(list: list, info: info, item: nil, transport: transport)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, [externalURL.path])
        XCTAssertFalse(recorder.emitted.first?.sourcePaths.contains("/stale/internal") ?? true)
    }

    /// EOP-002: copy-only source mask와 Option 없음은 copy로 resolve한다.
    func testCopyOnlySourceMaskResolvesCopyWithOptionDrag() {
        let transport = DragTransport(paths: ["/source/file.txt"])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let collectionView = NSCollectionView()
        let info = DragInfoFixture(
            source: collectionView,
            operationMask: .copy,
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: []),
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, collectionView: collectionView)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, ["/source/file.txt"])
        XCTAssertEqual(recorder.emitted.first?.destinationPath, "/destination")
        XCTAssertEqual(recorder.emitted.first?.isOptionDrag, true)
    }

    /// EOP-002: source folder를 자신의 descendant destination으로 drop하면 거부한다.
    func testSourceFolderIntoOwnDescendantDestinationIsRejected() {
        let transport = DragTransport(paths: ["/source/folder"])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/source/folder/child"

        let collectionView = NSCollectionView()
        let info = DragInfoFixture(
            source: collectionView,
            operationMask: [.copy, .move],
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: []),
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, collectionView: collectionView)

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    /// EOP-002: move-allowed mask와 Option 없음은 move로 resolve한다.
    func testMoveAllowedMaskResolvesMoveWithoutOptionDrag() {
        let transport = DragTransport(paths: ["/source/file.txt"])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let collectionView = NSCollectionView()
        let info = DragInfoFixture(
            source: collectionView,
            operationMask: .move,
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: []),
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, collectionView: collectionView)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, ["/source/file.txt"])
        XCTAssertEqual(recorder.emitted.first?.destinationPath, "/destination")
        XCTAssertEqual(recorder.emitted.first?.isOptionDrag, false)
    }

    /// EOP-002: supported + unsupported mixed payload는 원자적으로 전체 거절한다.
    func testMixedPayloadIsAtomicallyRejected() {
        let transport = DragTransport(paths: [])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let externalURL = URL(fileURLWithPath: "/external/mixed.txt")
        let pasteboard = DragInfoFixture.makeMixedPasteboard(
            fileURL: externalURL,
            unsupportedText: "unsupported",
        )
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    /// EOP-002: empty payload는 no operation이다.
    func testEmptyPayloadProducesNoOperation() {
        let transport = DragTransport(paths: [])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy, .move],
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: []),
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    /// EOP-002: unsupported-only payload는 no operation이다.
    func testUnsupportedOnlyPayloadProducesNoOperation() {
        let transport = DragTransport(paths: [])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let pasteboard = DragInfoFixture.makeUnsupportedOnlyPasteboard(text: "not a file")
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    func testNonFileURLPayloadProducesNoOperation() {
        let pasteboard = DragInfoFixture.makeNonFileURLPasteboard()

        XCTAssertTrue(EntryViewLayoutDropValidationAdapter.sourcePaths(from: pasteboard).isEmpty)
    }

    /// EOP-002: accept-reject terminal path는 stale transport를 정리한다.
    func testAcceptRejectClearsStaleTransport() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy, .move],
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: []),
        )

        _ = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertFalse(store.state.isDropTargeted)
        XCTAssertTrue(recorder.emitted.isEmpty)
        XCTAssertTrue(transport.paths.isEmpty)
    }

    /// EOP-002: cancel terminal path는 stale transport를 정리한다.
    func testCancelClearsStaleTransport() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let store = makeStore(transport: transport, recorder: DropRecorder())
        let grid = EntryGridCoordinator(store: store)
        store.send(.view(.setDropTargeted(true)))

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            grid.collectionView(NSCollectionView(), draggingSession: .init(), endedAt: .zero, dragOperation: [])
        }

        XCTAssertFalse(store.state.isDropTargeted)
    }

    /// EOP-002 (FIX 7): 외부 session 진입(List validateDrop)은 stale transport를 정리해 다음 session 격리를 보장한다.
    func testExternalEntryClearsStaleTransport() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let store = makeStore(transport: transport, recorder: DropRecorder(), currentPath: "/current")
        let list = EntryListCoordinator(store: store)

        let externalURL = URL(fileURLWithPath: "/external/entry.txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            _ = list.outlineView(NSOutlineView(), validateDrop: info, proposedItem: nil, proposedChildIndex: 0)
        }

        XCTAssertTrue(
            transport.paths.isEmpty,
            "외부 session 진입 시 stale transport를 무효화해야 한다",
        )
    }

    // MARK: - EOP-002-drop_external_entries_on_directory_page (destination routing + parity)

    /// EOP-002: blank target은 Grid/List 모두 currentPath로 route한다.
    func testBlankDestinationRoutingMatchesGridAndList() throws {
        let transport = DragTransport(paths: [])
        let externalURL = URL(fileURLWithPath: "/external/blank.txt")

        let gridEmit = try driveGridAccept(
            transport: transport,
            currentPath: "/current",
            itemPath: nil,
            externalURL: externalURL,
        )
        let listEmit = try driveListAccept(
            transport: transport,
            currentPath: "/current",
            itemPath: nil,
            externalURL: externalURL,
        )

        XCTAssertEqual(gridEmit.sourcePaths, listEmit.sourcePaths)
        XCTAssertEqual(gridEmit.destinationPath, "/current")
        XCTAssertEqual(gridEmit.destinationPath, listEmit.destinationPath)
        XCTAssertEqual(gridEmit.isOptionDrag, listEmit.isOptionDrag)
    }

    /// EOP-002: Directory Entry target은 Grid/List 모두 entry.fullPath로 route한다.
    func testDirectoryDestinationRoutingMatchesGridAndList() throws {
        let transport = DragTransport(paths: [])
        let externalURL = URL(fileURLWithPath: "/external/folder-drop.txt")

        let gridEmit = try driveGridAccept(
            transport: transport,
            currentPath: "/current",
            itemPath: "/dest/folder",
            externalURL: externalURL,
        )
        let listEmit = try driveListAccept(
            transport: transport,
            currentPath: "/current",
            itemPath: "/dest/folder",
            externalURL: externalURL,
        )

        XCTAssertEqual(gridEmit.sourcePaths, listEmit.sourcePaths)
        XCTAssertEqual(gridEmit.destinationPath, "/dest/folder")
        XCTAssertEqual(gridEmit.destinationPath, listEmit.destinationPath)
        XCTAssertEqual(gridEmit.isOptionDrag, listEmit.isOptionDrag)
    }

    /// EOP-002: package directory는 destination에서 제외해 currentPath로 route한다.
    func testPackageDirectoryIsExcludedFromListDestination() {
        let transport = DragTransport(paths: [])
        let recorder = DropRecorder()
        let externalURL = URL(fileURLWithPath: "/external/pkg.txt")
        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current")
        let list = EntryListCoordinator(store: store)

        let folderEntry = makePackageFolder(id: "/pkg.app")
        let outlineItem = EntryListCoordinator.OutlineItem(kind: .entry(folderEntry))
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveListAccept(list: list, info: info, item: outlineItem, transport: transport)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, [externalURL.path])
        XCTAssertEqual(
            recorder.emitted.first?.destinationPath,
            "/current",
            "package directory는 destination으로 route하지 않아야 한다",
        )
    }
}

// MARK: - Support

@MainActor
private extension EOP002ArrangeEntriesTests {
    func makeStore(
        transport: DragTransport,
        recorder: DropRecorder,
        currentPath: String = "/current",
    ) -> StoreOf<EntryViewLayoutFeature> {
        var state = EntryViewLayoutState()
        state.currentPath = currentPath
        return Store(initialState: state) {
            DropRecordingReducer(recorder: recorder, inner: EntryViewLayoutFeature())
        } withDependencies: {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
            $0.entryLoadingClient = EntryLoadingClient.testValue
        }
    }

    func makeFileOpsClient(transport: DragTransport) -> EntryFileOpsClient {
        var client = EntryFileOpsClient.testValue
        client.saveDragPaths = { transport.paths = $0 }
        client.loadDragPaths = { transport.paths }
        client.saveDragWithOption = { transport.option = $0 }
        client.loadDragWithOption = { transport.option }
        // dropItems가 내부로 전파되어 실제 파일 작업을 실행하지 않도록 no-op으로 둔다.
        client.pasteFile = { _, _ in }
        client.moveFile = { _, _ in }
        return client
    }

    func makePackageFolder(id: String) -> EntryModel {
        EntryModel(
            name: URL(fileURLWithPath: id).lastPathComponent,
            fullPath: id,
            isFolder: true,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: "app",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "Application",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
            isPackage: true,
        )
    }

    @discardableResult
    func driveGridAccept(
        grid: EntryGridCoordinator,
        info: any NSDraggingInfo,
        transport: DragTransport,
        collectionView: NSCollectionView = NSCollectionView(),
    ) -> Bool {
        var accepted = false
        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            accepted = grid.collectionView(
                collectionView,
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }
        return accepted
    }

    @discardableResult
    func driveListAccept(
        list: EntryListCoordinator,
        info: any NSDraggingInfo,
        item: Any?,
        transport: DragTransport,
    ) -> Bool {
        var accepted = false
        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            accepted = list.outlineView(NSOutlineView(), acceptDrop: info, item: item, childIndex: 0)
        }
        return accepted
    }

    func driveGridAccept(
        transport: DragTransport,
        currentPath: String,
        itemPath: String?,
        externalURL: URL,
    ) throws -> EmittedDrop {
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder, currentPath: currentPath)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = itemPath

        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)
        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        return try XCTUnwrap(recorder.emitted.first)
    }

    func driveListAccept(
        transport: DragTransport,
        currentPath: String,
        itemPath: String?,
        externalURL: URL,
    ) throws -> EmittedDrop {
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder, currentPath: currentPath)
        let list = EntryListCoordinator(store: store)

        let outlineItem: EntryListCoordinator.OutlineItem?
        if let itemPath {
            let folderEntry = EntryModel.temporaryFolder(id: itemPath, name: (itemPath as NSString).lastPathComponent)
            outlineItem = EntryListCoordinator.OutlineItem(kind: .entry(folderEntry))
        } else {
            outlineItem = nil
        }

        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveListAccept(list: list, info: info, item: outlineItem, transport: transport)
        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        return try XCTUnwrap(recorder.emitted.first)
    }
}

@MainActor
private extension DragInfoFixture {
    static func makeFileURLPasteboard(urls: [URL]) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-\(UUID().uuidString)"))
        pasteboard.clearContents()
        if !urls.isEmpty {
            pasteboard.writeObjects(urls as [NSURL])
        }
        return pasteboard
    }

    static func makeMixedPasteboard(fileURL: URL, unsupportedText: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-mixed-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL, unsupportedText as NSString])
        return pasteboard
    }

    static func makeUnsupportedOnlyPasteboard(text: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-unsupported-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([text as NSString])
        return pasteboard
    }

    static func makeNonFileURLPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-non-file-url-\(UUID().uuidString)"))
        let item = NSPasteboardItem()
        item.setString("https://example.com/not-a-file", forType: .fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return pasteboard
    }
}
