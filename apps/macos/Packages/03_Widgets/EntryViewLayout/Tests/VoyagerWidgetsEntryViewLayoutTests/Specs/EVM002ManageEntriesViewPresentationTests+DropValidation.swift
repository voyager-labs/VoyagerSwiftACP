import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    /// EVM-002-manage_entries_view: move 선호 drag가 copy-only mask를 따르면 copy로 fallback한다.
    /// - 검증 내용: AppKit source operation mask가 canonical drop validation에 전달된다.
    /// - 사전 조건: Option 키 없이 copy만 허용된 drag source다.
    /// - 기대 결과: resolved operation이 copy이고 isOptionDrag가 true다.
    func testDropValidationPreservesCopyOnlySourceMask() {
        let result = EntryViewLayoutDropValidationAdapter.resolve(
            sourcePaths: ["/source/file.txt"],
            destinationPath: "/destination",
            allowedOperations: .copy,
            prefersCopy: false,
        )

        XCTAssertEqual(result.resolvedOperation, .copy)
        XCTAssertTrue(result.isOptionDrag)
    }

    /// EVM-002-manage_entries_view: source folder 하위 destination drop을 거부한다.
    /// - 검증 내용: coordinator adapter가 canonical descendant rejection을 재사용한다.
    /// - 사전 조건: source folder를 자신의 하위 경로로 move하려 한다.
    /// - 기대 결과: resolved operation이 none이다.
    func testDropValidationRejectsDescendantDestination() {
        let result = EntryViewLayoutDropValidationAdapter.resolve(
            sourcePaths: ["/source/folder"],
            destinationPath: "/source/folder/child",
            allowedOperations: [.copy, .move],
            prefersCopy: false,
        )

        XCTAssertEqual(result.resolvedOperation, .none)
    }

    /// EVM-002-manage_entries_view: UTType.fileURL로 위장한 https URL item은 원자적으로 거부된다.
    /// file-URL pasteboard type을 광고하지만 실제 파일 URL이 아닌 item이 있으면 전체 drop session을 거부해야 한다.
    /// - 검증 내용: `sourcePaths(from:)`이 file URL이 아닌 항목이 섞인 pasteboard에서 빈 배열을 반환한다.
    /// - 사전 조건: UTType.fileURL 타입으로 https URL 문자열을 등록한 pasteboard item을 준비한다.
    /// - 기대 결과: sourcePaths가 비어 있어 외부 drop session이 atomically 거부된다.
    func testSourcePathsRejectsNonFileURLAdvertisedAsFileURL() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("voyager.test.drop.https.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("https://example.com/file.txt", forType: .fileURL)
        pasteboard.writeObjects([item])

        let sourcePaths = EntryViewLayoutDropValidationAdapter.sourcePaths(from: pasteboard)

        XCTAssertTrue(sourcePaths.isEmpty)
    }

    // MARK: - EVM-002-manage_entries_view_list_drop_destination

    /// EVM-002-manage_entries_view_list_drop_destination: `.voycoll` 디렉터리(live 변환상 package)는 list drop destination이 되지
    /// 않는다.
    /// live 변환은 `.voycoll` 디렉터리를 `isPackage:true`로 분류하므로 기존 `isFolder && !isPackage` guard가 이미 거부한다.
    /// - 검증 내용: voycoll package가 proposed item일 때 drop이 현재 폴더(currentPath)로 fallback된다.
    /// - 사전 조건: /root/Collection.voycoll package folder가 proposed item이고 source 파일이 그 안에 있다.
    /// - 기대 결과: validateDrop이 non-empty operation을 반환하고 store의 isDropTargeted가 true다.
    func testValidateDropExcludesVoycollDirectoryAsDropDestination() {
        let voycoll = makeVoycollPackageFolder(id: "/root/Collection.voycoll")
        var state = EntryViewLayoutState()
        state.currentPath = "/root"
        state.entries = [voycoll]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        let voycollItem = EntryListOutlineItem(kind: .entry(voycoll))
        let spy = makeDraggingInfo(sourcePath: "/root/Collection.voycoll/file.txt", operation: .move)

        let operation = coordinator.outlineView(
            coordinator.tableView,
            validateDrop: spy,
            proposedItem: voycollItem,
            proposedChildIndex: 0,
        )

        XCTAssertFalse(operation.isEmpty)
        XCTAssertTrue(store.state.isDropTargeted)
    }

    /// EVM-002-manage_entries_view_list_drop_destination: `.voycoll` 디렉터리(live 변환상 package)도 acceptDrop의 destination이
    /// 되지 않는다.
    /// - 검증 내용: voycoll package로의 drop이 destinationPath를 currentPath로 fallback해 accept된다.
    /// - 사전 조건: /root/Collection.voycoll package folder가 proposed item이고 source 파일이 그 안에 있다.
    /// - 기대 결과: acceptDrop이 true를 반환한다.
    func testAcceptDropExcludesVoycollDirectoryAsDropDestination() {
        let voycoll = makeVoycollPackageFolder(id: "/root/Collection.voycoll")
        var state = EntryViewLayoutState()
        state.currentPath = "/root"
        state.entries = [voycoll]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        let voycollItem = EntryListOutlineItem(kind: .entry(voycoll))
        let spy = makeDraggingInfo(sourcePath: "/root/Collection.voycoll/file.txt", operation: .move)

        let accepted = coordinator.outlineView(
            coordinator.tableView,
            acceptDrop: spy,
            item: voycollItem,
            childIndex: 0,
        )

        XCTAssertTrue(accepted)
    }

    /// EVM-002-manage_entries_view_list_drop_destination: `.voycoll` 디렉터리(live 변환상 package)는 grid drop의 `.on` 대상이 되지
    /// 않는다.
    /// - 검증 내용: voycoll package entry가 resolved target이어도 validateDrop이 `.on` operation을 세우지 않고 `.before`로 두고
    /// destinationPath를 currentPath로 유지한다.
    /// - 사전 조건: grid에 /root/Collection.voycoll package folder가 있고 그 index path가 proposed index path로 주어진다.
    /// - 기대 결과: proposedDropOperation이 `.on`이 아니며 destinationPath가 currentPath("/root")로 유지된다.
    func testGridValidateDropExcludesVoycollDirectoryAsOnTarget() {
        let voycoll = makeVoycollPackageFolder(id: "/root/Collection.voycoll")
        var state = EntryViewLayoutState()
        state.currentPath = "/root"
        state.entries = [voycoll]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.view = view
        coordinator.sections = [
            EntryGridSection(title: nil, colorCode: nil, count: 1, items: [voycoll], isCollapsed: false),
        ]
        coordinator.indexPathByEntryId = [voycoll.id: IndexPath(item: 0, section: 0)]

        var proposedIndexPath: NSIndexPath? = NSIndexPath(forItem: 0, inSection: 0)
        let proposedIndexPathPtr = AutoreleasingUnsafeMutablePointer<NSIndexPath>(&proposedIndexPath)
        var dropOperation = NSCollectionView.DropOperation.before
        let proposedDropOperation = UnsafeMutablePointer<NSCollectionView.DropOperation>(&dropOperation)
        let spy = makeDraggingInfo(sourcePath: "/root/Collection.voycoll/file.txt", operation: .move)

        _ = coordinator.collectionView(
            view.collectionView,
            validateDrop: spy,
            proposedIndexPath: proposedIndexPathPtr,
            dropOperation: proposedDropOperation,
        )

        XCTAssertNotEqual(proposedDropOperation.pointee, .on, "voycoll package directory는 grid drop `.on` 대상이 되면 안 된다")
    }

    /// EVM-002-manage_entries_view_list_drop_destination: package directory는 list drop destination이 되지 않는다.
    /// package entry는 `isFolder`가 true여도 `!isPackage` 조건으로 destination에서 제외되어
    /// drop이 현재 폴더(currentPath)로 fallback된다.
    /// - 검증 내용: source가 package 내부에 있을 때 package로의 move가 no-op 거부되는 대신 현재 폴더로 accept된다.
    /// - 사전 조건: /root/Voyager.app package folder가 proposed item이고 source 파일이 그 package 안에 있다.
    /// - 기대 결과: validateDrop이 non-empty operation을 반환하고 store의 isDropTargeted가 true다.
    func testValidateDropExcludesPackageAsDropDestination() {
        let package = makePackageFolder(id: "/root/Voyager.app")
        var state = EntryViewLayoutState()
        state.currentPath = "/root"
        state.entries = [package]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        let packageItem = EntryListOutlineItem(kind: .entry(package))
        let spy = makeDraggingInfo(sourcePath: "/root/Voyager.app/file.txt", operation: .move)

        let operation = coordinator.outlineView(
            coordinator.tableView,
            validateDrop: spy,
            proposedItem: packageItem,
            proposedChildIndex: 0,
        )

        XCTAssertFalse(operation.isEmpty)
        XCTAssertTrue(store.state.isDropTargeted)
    }

    /// EVM-002-manage_entries_view_list_drop_destination: acceptDrop도 package directory를 destination으로 삼지 않는다.
    /// - 검증 내용: package로의 drop이 destinationPath를 currentPath로 fallback해 accept된다.
    /// - 사전 조건: /root/Voyager.app package folder가 proposed item이고 source 파일이 그 package 안에 있다.
    /// - 기대 결과: acceptDrop이 true를 반환한다.
    func testAcceptDropExcludesPackageAsDropDestination() {
        let package = makePackageFolder(id: "/root/Voyager.app")
        var state = EntryViewLayoutState()
        state.currentPath = "/root"
        state.entries = [package]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        let packageItem = EntryListOutlineItem(kind: .entry(package))
        let spy = makeDraggingInfo(sourcePath: "/root/Voyager.app/file.txt", operation: .move)

        let accepted = coordinator.outlineView(
            coordinator.tableView,
            acceptDrop: spy,
            item: packageItem,
            childIndex: 0,
        )

        XCTAssertTrue(accepted)
    }

    /// EVM-002-manage_entries_view_list_drop_destination: 일반 folder는 여전히 유효한 list drop destination이다.
    /// - 검증 내용: package가 아닌 일반 folder는 validateDrop과 acceptDrop 모두에서 destination으로 유지된다.
    /// - 사전 조건: /root/Documents 일반 folder가 proposed item이고 source 파일이 그 folder 밖에 있다.
    /// - 기대 결과: validateDrop이 non-empty operation을 반환하고 acceptDrop이 true를 반환한다.
    func testNormalFolderRemainsValidDropDestination() {
        let folder = EntryModel.temporaryFolder(id: "/root/Documents", name: "Documents")
        var state = EntryViewLayoutState()
        state.currentPath = "/root"
        state.entries = [folder]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        let folderItem = EntryListOutlineItem(kind: .entry(folder))
        let spy = makeDraggingInfo(sourcePath: "/root/Voyager.app/file.txt", operation: .move)

        let operation = coordinator.outlineView(
            coordinator.tableView,
            validateDrop: spy,
            proposedItem: folderItem,
            proposedChildIndex: 0,
        )
        XCTAssertFalse(operation.isEmpty)
        XCTAssertTrue(store.state.isDropTargeted)

        let accepted = coordinator.outlineView(
            coordinator.tableView,
            acceptDrop: spy,
            item: folderItem,
            childIndex: 0,
        )
        XCTAssertTrue(accepted)
    }

    /// EVM-002-manage_entries_view_list_drop_destination: `acceptsDropInto` 정책이 `isFolder && !isPackage`와 동치인지 행렬 검증.
    /// - 검증 내용: ordinary dir만 drop interior 대상이고, package(`.app`/`.voycoll`)와 file은 대상이 아니다.
    /// - 사전 조건: 각 fixture가 주어진 isFolder/isPackage 조합을 가진다.
    /// - 기대 결과: ordinary dir → true, `.app` → false, voycoll dir → false, file → false.
    func testAcceptsDropIntoMatrixMatchesIsFolderAndNotPackage() {
        let ordinary = EntryModel.temporaryFolder(id: "/root/Documents", name: "Documents")
        let app = makePackageFolder(id: "/root/Voyager.app")
        let voycoll = makeVoycollPackageFolder(id: "/root/Collection.voycoll")
        let file = makeFile(id: "/root/note.txt", name: "note.txt")

        XCTAssertTrue(ordinary.acceptsDropInto, "ordinary directory는 drop interior 대상이어야 한다")
        XCTAssertFalse(app.acceptsDropInto, "`.app` package directory는 drop interior 대상이 아니어야 한다")
        XCTAssertFalse(voycoll.acceptsDropInto, "`.voycoll` directory(live 변환상 package)는 drop interior 대상이 아니어야 한다")
        XCTAssertFalse(file.acceptsDropInto, "file은 drop interior 대상이 아니어야 한다")
    }
}

private func makePackageFolder(id: String) -> EntryModel {
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

private func makeVoycollPackageFolder(id: String) -> EntryModel {
    EntryModel(
        name: URL(fileURLWithPath: id).lastPathComponent,
        fullPath: id,
        isFolder: true,
        isHidden: false,
        size: 0,
        modifiedDate: Date(timeIntervalSince1970: 0),
        fileExtension: "voycoll",
        facets: .init(
            createdDate: Date(timeIntervalSince1970: 0),
            addedDate: Date(timeIntervalSince1970: 0),
            lastOpenedDate: nil,
            kind: "Voyager Collection",
            creatorApplication: nil,
            tags: nil,
            supplementaryMetadata: nil,
        ),
        isPackage: true,
    )
}

private func makeFile(id: String, name: String) -> EntryModel {
    EntryModel(
        name: name,
        fullPath: id,
        isFolder: false,
        isHidden: false,
        size: 0,
        modifiedDate: Date(timeIntervalSince1970: 0),
        fileExtension: URL(fileURLWithPath: id).pathExtension,
        facets: .init(
            createdDate: Date(timeIntervalSince1970: 0),
            addedDate: Date(timeIntervalSince1970: 0),
            lastOpenedDate: nil,
            kind: "Plain Text",
            creatorApplication: nil,
            tags: nil,
            supplementaryMetadata: nil,
        ),
        isPackage: false,
    )
}

@MainActor
private func makeDraggingInfo(
    sourcePath: String,
    operation: NSDragOperation,
) -> DraggingInfoSpy {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("voyager.test.drop.\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.writeObjects([NSURL(fileURLWithPath: sourcePath)])
    return DraggingInfoSpy(pasteboard: pasteboard, operation: operation)
}

@MainActor
private final class DraggingInfoSpy: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard
    let operation: NSDragOperation

    init(pasteboard: NSPasteboard, operation: NSDragOperation) {
        self.pasteboard = pasteboard
        self.operation = operation
        super.init()
    }

    var draggingDestinationWindow: NSWindow? {
        nil
    }

    var draggingSourceOperationMask: NSDragOperation {
        operation
    }

    var draggingLocation: NSPoint {
        .zero
    }

    var draggedImageLocation: NSPoint {
        .zero
    }

    nonisolated var draggedImage: NSImage? {
        nil
    }

    var draggingPasteboard: NSPasteboard {
        pasteboard
    }

    var draggingSource: Any? {
        nil
    }

    var draggingSequenceNumber: Int {
        0
    }

    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0

    var springLoadingHighlight: NSSpringLoadingHighlight {
        .none
    }

    func slideDraggedImage(to _: NSPoint) {}
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions,
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any],
        using _: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void,
    ) {}
    override nonisolated func namesOfPromisedFilesDropped(atDestination _: URL) -> [String]? {
        nil
    }
}
