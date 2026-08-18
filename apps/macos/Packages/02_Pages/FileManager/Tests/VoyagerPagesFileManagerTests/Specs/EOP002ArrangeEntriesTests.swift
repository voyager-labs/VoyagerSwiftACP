import ComposableArchitecture
import Foundation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class EOP002ArrangeEntriesTests: XCTestCase {
    // MARK: - EOP-002-import_external_objects (aggregate reload bridge)

    /// EOP-002-import_external_objects: 외부 import per-item finish는 reload하지 않고 종합 완료가 정확히 한 번 reload한다.
    /// `.externalObjectImportItem` 항목별 `operationFinished`는 Folder/route reload를 유발하지 않고,
    /// 종합 `.externalDrop(.importFinished)`가 정확히 한 번 `loadItems`(reload)를 일으킨다.
    /// - 검증 내용: per-item finish reload 0회, aggregate importFinished reload 1회.
    func testExternalImportAggregateTriggersExactlyOneReload() async {
        let windowID = UUID()
        let tabID = ContentTabID(rawValue: "A")
        let path = "/tmp/A"
        let state = makeSingleTabFolderState(windowID: windowID, tabID: tabID, path: path)

        let loadCounter = LoadCounter()
        let store = makeStore(state: state) {
            $0.entryLoadingClient.loadItems = { receivedURL, _ in
                loadCounter.record()
                XCTAssertEqual(receivedURL.path, path)
                return []
            }
        }
        store.exhaustivity = .off

        let sessionID = ExternalDropSessionID()
        let sourcePath = "\(path)/staged.txt"

        // per-item finish: reload를 유발하면 안 된다.
        await store.send(.tabContent(
            tabID: tabID,
            action: .entryViewLayout(.entryOperations(.lifecycle(.operationFinished(
                sourcePath,
                .externalObjectImportItem,
                .success(()),
            )))),
        ))
        await store.finish()
        XCTAssertEqual(loadCounter.count, 0, "per-item external-import finish must not reload")

        // 종합 완료: 정확히 한 번 reload한다.
        let result = ExternalDropImportResult(
            sessionID: sessionID,
            succeededPaths: ["\(path)/staged.txt"],
            failedPaths: [],
            status: .applied,
        )
        await store.send(.tabContent(
            tabID: tabID,
            action: .entryViewLayout(.entryOperations(.externalDrop(.importFinished(result)))),
        ))
        await store.finish()
        XCTAssertEqual(loadCounter.count, 1, "aggregate external-import terminal must reload exactly once")
    }

    // MARK: - Helpers

    private func makeSingleTabFolderState(
        windowID: UUID,
        tabID: ContentTabID,
        path: String,
    ) -> FileManagerWindowState {
        var content = FileManagerContentFeature.State()
        content.navigation.seedInitialFolderPath(path)
        content.entryViewLayout.entryOperations.windowID = windowID

        var state = FileManagerWindowState()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .directory,
                anchor: .directory(path: path),
                isPinned: false,
                title: tabID.rawValue,
                iconName: "folder",
            )],
            activeTabID: tabID,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.syncContentTabSidebarItems()
        return state
    }

    private func makeStore(
        state: FileManagerWindowState,
        configure: (inout DependencyValues) -> Void = { _ in },
    ) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
        TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            )
            configure(&$0)
        }
    }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    func record() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }
}
