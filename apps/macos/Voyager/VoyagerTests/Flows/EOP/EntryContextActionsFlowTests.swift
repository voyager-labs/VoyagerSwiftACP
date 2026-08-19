// FLOW-ID: eop.entry_context_actions
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryContextActionsFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.share_selected_entries

    /// EOP-007-share_entries_via_system_share_sheet: 선택한 fixture Entry를 공유한다.
    /// EntryViewLayout command delegate가 부모 planner를 거쳐 mock share boundary로 전달되는지 검증한다.
    /// - 검증 내용: 선택 fixture URL과 nil anchor가 EntryOpenClient.shareItems로 전달되고 page와 selection이 유지된다.
    /// - 사전 조건: sandbox fixture가 selection에 있고 EntryOpenClient.shareItems가 recorder로 대체되어 있다.
    /// - 기대 결과: 실제 macOS Share Sheet 없이 하나의 boundary 호출만 기록되고 Voyager 상태는 변경되지 않는다.
    func testShareSelectedItemsThroughProductionComposition() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let entry = makeEntry(at: sandbox.fileURL)
        let shareCalls = LockIsolated<[ShareBoundaryCall]>([])
        let store = makeStore(
            rootPath: sandbox.root.path,
            entries: [entry],
            selectedIDs: [entry.id],
            shareCalls: shareCalls,
        )
        // store.exhaustivity = .off: 부모 bridge와 비동기 operation lifecycle보다 boundary payload와 상태 보존을 검증한다.
        store.exhaustivity = .off
        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        let initialSelection = store.state.entryViewLayout.selectedIds

        await store.send(.entryViewLayout(.delegate(.executeCommand("navigation.shareSelectedItems"))))
        await store.finish()

        XCTAssertEqual(
            shareCalls.withValue { $0 },
            [.init(urls: [sandbox.fileURL], anchor: nil)],
        )
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, initialSelection)
        XCTAssertEqual(shareCalls.withValue(\.count), 1)
    }

    // FLOW-PATH: alternate_path.empty_selection_preserves_state

    /// EOP-007-share_entries_via_system_share_sheet: 빈 selection은 공유 경계를 호출하지 않는다.
    /// EntryViewLayout command delegate가 빈 selection으로 parent planner에 도달해도 no-op인지 검증한다.
    /// - 검증 내용: EntryOpenClient.shareItems recorder가 비어 있고 page와 selection이 유지된다.
    /// - 사전 조건: Directory Page에 fixture Entry는 있지만 선택된 Entry가 없다.
    /// - 기대 결과: macOS Share Sheet boundary 호출이나 Voyager Entry/listing mutation이 없다.
    func testShareSelectedItemsWithEmptySelectionDoesNotCallBoundary() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let entry = makeEntry(at: sandbox.fileURL)
        let shareCalls = LockIsolated<[ShareBoundaryCall]>([])
        let store = makeStore(
            rootPath: sandbox.root.path,
            entries: [entry],
            selectedIDs: [],
            shareCalls: shareCalls,
        )
        // store.exhaustivity = .off: 부모 bridge가 만든 command routing의 no-op 결과와 상태 보존을 검증한다.
        store.exhaustivity = .off
        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory
        let initialSelection = store.state.entryViewLayout.selectedIds

        await store.send(.entryViewLayout(.delegate(.executeCommand("navigation.shareSelectedItems"))))
        await store.finish()

        XCTAssertTrue(shareCalls.withValue { $0.isEmpty })
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, initialSelection)
    }

    private func makeStore(
        rootPath: String,
        entries: [EntryModel],
        selectedIDs: Set<EntryModel.ID>,
        shareCalls: LockIsolated<[ShareBoundaryCall]>,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.entryOperations.items = IdentifiedArray(uniqueElements: entries)
        state.entryViewLayout.entries = entries
        state.entryViewLayout.selectedIds = selectedIDs
        return TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryOpenClient.shareItems = { urls, anchor in
                shareCalls.withValue { $0.append(.init(urls: urls, anchor: anchor)) }
            }
        }
    }

    private func makeEntry(at url: URL) -> EntryModel {
        EntryModel(
            name: url.lastPathComponent,
            fullPath: url.path,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: url.pathExtension,
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "Plain Text",
                creatorApplication: nil,
                tags: [],
                supplementaryMetadata: nil,
            ),
        )
    }
}

private struct ShareBoundaryCall: Equatable {
    let urls: [URL]
    let anchor: CGPoint?
}
