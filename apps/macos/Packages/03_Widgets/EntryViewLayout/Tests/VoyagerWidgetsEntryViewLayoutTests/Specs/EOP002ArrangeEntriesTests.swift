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
    // MARK: - EOP-002-drop_external_entries_on_directory_page

    /// EOP-002-drop_external_entries_on_directory_page: stale internal path가 있어도 외부 drag는 현재 external URL만 source로 쓴다.
    /// origin을 저장된 path 비어있음이 아니라 `draggingSource` identity로 분류해야 한다.
    /// - 검증 내용: named transport에 stale internal path를 seed하고 외부 drag를 accept하면 emit된 dropItems source가 external URL
    /// 하나뿐이다.
    /// - 사전 조건: `VoyagerDragDrop` transport에 `["/stale/internal"]`이 남아 있고, `draggingSource`가 layout source가 아닌 외부 drag가
    /// file URL을 제공한다.
    /// - 기대 결과: emit된 source는 `["/external/url"]`만이고 stale path는 절대 포함하지 않는다.
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

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            _ = grid.collectionView(
                NSCollectionView(),
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }

        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(
            recorder.emitted.first?.sourcePaths,
            [externalURL.path],
            "external drag는 stale internal path 대신 active external URL만 source로 사용해야 한다",
        )
    }

    /// EOP-002-drop_external_entries_on_directory_page: copy-only source mask와 Option 없음은 copy로 resolve한다.
    /// copy-only source를 move로 승격하지 않는다 (`02bf1e1f7` 이후 semantics).
    /// - 검증 내용: `.copy` mask + no Option drag에서 accept가 `.copy`를 emit하고 `isOptionDrag=true`다.
    /// - 사전 조건: source mask가 `.copy`만 허용하고 Option modifier가 없는 drag다.
    /// - 기대 결과: resolved operation이 copy이고 `isOptionDrag`가 true다.
    func testCopyOnlySourceMaskResolvesCopyWithOptionDrag() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(
            source: nil,
            operationMask: .copy,
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: [
                URL(fileURLWithPath: "/source/file.txt"),
            ]),
        )

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            _ = grid.collectionView(
                NSCollectionView(),
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }

        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, ["/source/file.txt"])
        XCTAssertEqual(recorder.emitted.first?.destinationPath, "/destination")
        XCTAssertTrue(
            recorder.emitted.first?.isOptionDrag == true,
            "copy-only source는 copy로 resolve되어 isOptionDrag=true여야 한다",
        )
    }

    /// EOP-002-drop_external_entries_on_directory_page: source folder의 자신 하위 destination drop을 거부한다.
    /// canonical descendant rejection을 그대로 재사용한다.
    /// - 검증 내용: source folder를 자신의 descendant destination으로 drop하면 accept가 거부된다.
    /// - 사전 조건: source `/source/folder`를 destination `/source/folder/child`로 move하려 한다.
    /// - 기대 결과: resolved operation이 none이고 accept가 false며 dropItems를 emit하지 않는다.
    func testSourceFolderIntoOwnDescendantDestinationIsRejected() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/source/folder/child"

        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy, .move],
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: [
                URL(fileURLWithPath: "/source/folder"),
            ]),
        )

        var accepted = true
        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            accepted = grid.collectionView(
                NSCollectionView(),
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    /// EOP-002-drop_external_entries_on_directory_page: move-allowed mask와 Option 없음은 move로 resolve한다.
    /// - 검증 내용: `.move` mask + no Option drag에서 accept가 move를 emit하고 `isOptionDrag=false`다.
    /// - 사전 조건: source mask가 move를 허용하고 Option modifier가 없는 drag다.
    /// - 기대 결과: resolved operation이 move이고 `isOptionDrag`가 false다.
    func testMoveAllowedMaskResolvesMoveWithoutOptionDrag() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(
            source: nil,
            operationMask: .move,
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: [
                URL(fileURLWithPath: "/source/file.txt"),
            ]),
        )

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            _ = grid.collectionView(
                NSCollectionView(),
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }

        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, ["/source/file.txt"])
        XCTAssertFalse(
            recorder.emitted.first?.isOptionDrag == true,
            "move-allowed source는 move로 resolve되어 isOptionDrag=false여야 한다",
        )
    }

    /// EOP-002-drop_external_entries_on_directory_page: supported + unsupported mixed payload는 원자적으로 전체 거절한다.
    /// full `pasteboardItems`를 검사하고 unsupported item을 `readObjects`로 조용히 걸러내지 않는다.
    /// - 검증 내용: file URL item과 unsupported item이 섞인 payload를 accept하면 dropItems를 emit하지 않는다.
    /// - 사전 조건: pasteboard에 file URL 1개와 지원하지 않는 item 1개가 함께 있다.
    /// - 기대 결과: source count가 0이고 부분 수용 없이 session 전체가 거절된다.
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
        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy, .move],
            pasteboard: pasteboard,
        )

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            _ = grid.collectionView(
                NSCollectionView(),
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }

        XCTAssertTrue(
            recorder.emitted.isEmpty,
            "mixed payload는 supported item만 부분 수용하지 않고 전체를 거절해야 한다",
        )
    }

    /// EOP-002-drop_external_entries_on_directory_page: empty payload는 no operation이다.
    /// - 검증 내용: file URL을 포함하지 않는 빈 pasteboard를 accept하면 dropItems를 emit하지 않는다.
    /// - 사전 조건: external drag pasteboard에 file URL item이 없다.
    /// - 기대 결과: accept가 false이고 source count가 0이다.
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

        var accepted = true
        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            accepted = grid.collectionView(
                NSCollectionView(),
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    /// EOP-002-drop_external_entries_on_directory_page: unsupported-only payload는 no operation이다.
    /// - 검증 내용: file URL 없이 지원하지 않는 item만 있는 pasteboard를 accept하면 dropItems를 emit하지 않는다.
    /// - 사전 조건: external drag pasteboard에 file URL이 하나도 없다.
    /// - 기대 결과: accept가 false이고 source count가 0이다.
    func testUnsupportedOnlyPayloadProducesNoOperation() {
        let transport = DragTransport(paths: [])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let pasteboard = DragInfoFixture.makeUnsupportedOnlyPasteboard(text: "not a file")
        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy, .move],
            pasteboard: pasteboard,
        )

        var accepted = true
        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            accepted = grid.collectionView(
                NSCollectionView(),
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    func testNonFileURLPayloadProducesNoOperation() {
        let pasteboard = DragInfoFixture.makeNonFileURLPasteboard()

        XCTAssertTrue(EntryViewLayoutDropValidationAdapter.sourcePaths(from: pasteboard).isEmpty)
    }

    func testAcceptRejectClearsDropTarget() {
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

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            _ = grid.collectionView(
                NSCollectionView(),
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }

        XCTAssertFalse(store.state.isDropTargeted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    func testCancelClearsDropTarget() {
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

    // MARK: - EOP-002-drop_external_entries_on_directory_page (destination routing + parity)

    /// EOP-002-drop_external_entries_on_directory_page: blank target은 Grid/List 모두 currentPath로 route한다.
    /// - 검증 내용: 빈 영역 drop에서 Grid와 List가 같은 `state.currentPath` destination을 emit한다.
    /// - 사전 조건: currentPath가 `/current`이고 빈 영역에 외부 file URL이 drop된다.
    /// - 기대 결과: Grid와 List 모두 destination이 `/current`이고 source/operation이 같다.
    func testBlankDestinationRoutingMatchesGridAndList() {
        let transport = DragTransport(paths: [])
        let externalURL = URL(fileURLWithPath: "/external/blank.txt")

        let gridEmit = driveGridAccept(
            transport: transport,
            currentPath: "/current",
            itemPath: nil,
            externalURL: externalURL,
        )
        let listEmit = driveListAccept(
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

    /// EOP-002-drop_external_entries_on_directory_page: Directory Entry target은 Grid/List 모두 entry.fullPath로 route한다.
    /// - 검증 내용: 폴더 entry 위 drop에서 Grid와 List가 같은 entry.fullPath destination을 emit한다.
    /// - 사전 조건: currentPath가 `/current`이고 `/dest/folder` 폴더 entry에 외부 file URL이 drop된다.
    /// - 기대 결과: Grid와 List 모두 destination이 `/dest/folder`이고 source/operation이 같다.
    func testDirectoryDestinationRoutingMatchesGridAndList() {
        let transport = DragTransport(paths: [])
        let externalURL = URL(fileURLWithPath: "/external/folder-drop.txt")

        let gridEmit = driveGridAccept(
            transport: transport,
            currentPath: "/current",
            itemPath: "/dest/folder",
            externalURL: externalURL,
        )
        let listEmit = driveListAccept(
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

    /// EOP-002-drop_external_entries_on_directory_page: package directory는 destination에서 제외한다.
    /// package directory entry 위 drop은 해당 path로 route하지 않는다.
    /// - 검증 내용: List accept가 package directory entry를 currentPath로 fallback한다.
    /// - 사전 조건: `/pkg.app` package folder entry 위에 외부 file URL이 drop된다.
    /// - 기대 결과: destination이 package path가 아니라 currentPath이다.
    func testPackageDirectoryIsExcludedFromListDestination() {
        let transport = DragTransport(paths: [])
        let externalURL = URL(fileURLWithPath: "/external/pkg.txt")
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current")
        let list = EntryListCoordinator(store: store)

        let folderEntry = makePackageFolder(id: "/pkg.app")
        let outlineItem = EntryListCoordinator.OutlineItem(kind: .entry(folderEntry))
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        var accepted = false
        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            accepted = list.outlineView(NSOutlineView(), acceptDrop: info, item: outlineItem, childIndex: 0)
        }

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.first?.destinationPath, "/current")
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

    func driveGridAccept(
        transport: DragTransport,
        currentPath: String,
        itemPath: String?,
        externalURL: URL,
    ) -> EmittedDrop {
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder, currentPath: currentPath)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = itemPath

        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            _ = grid.collectionView(
                NSCollectionView(),
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }

        return recorder.emitted.first ?? EmittedDrop(sourcePaths: [], destinationPath: "", isOptionDrag: false)
    }

    func driveListAccept(
        transport: DragTransport,
        currentPath: String,
        itemPath: String?,
        externalURL: URL,
    ) -> EmittedDrop {
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

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            _ = list.outlineView(NSOutlineView(), acceptDrop: info, item: outlineItem, childIndex: 0)
        }

        return recorder.emitted.first ?? EmittedDrop(sourcePaths: [], destinationPath: "", isOptionDrag: false)
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
