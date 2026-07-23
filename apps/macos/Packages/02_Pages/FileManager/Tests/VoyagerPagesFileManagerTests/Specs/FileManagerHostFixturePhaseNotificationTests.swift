import ComposableArchitecture
import Foundation
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class FileManagerHostFixturePhaseNotificationTests: XCTestCase {
    func test_fixtureStateSeedsWindowContextIntoReducerState() {
        let windowID = UUID()
        let state = FileManagerHostFixture.makeState(preset: .default, windowID: windowID)

        XCTAssertEqual(
            state.content.entryViewLayout.entryOperations.windowID,
            windowID,
        )
        XCTAssertEqual(state.content.composer.cancellationOwnerID, windowID)
    }

    func test_progressiveFixtureSeedsNavigationAndHierarchyBeforeExpansionStreamStarts() async {
        let state = FileManagerHostFixture.makeState(preset: .progressiveEntryLoading)
        let projectsID = "/Fixture/FileManager/Projects"
        XCTAssertEqual(state.content.navigation.currentPath, "/Fixture/FileManager")
        XCTAssertEqual(state.content.entryViewLayout.hierarchy.rootPath, "/Fixture/FileManager")

        let store = TestStore(initialState: state.content.entryViewLayout) {
            EntryViewLayoutFeature()
        } withDependencies: {
            FileManagerHostFixture.applyDependencies(
                to: &$0,
                undoManager: UndoManager(),
                progressiveEntryLoading: .success,
                windowID: UUID(),
                workspaceClient: .previewValue,
            )
        }
        store.exhaustivity = .off // host launch 없이 expansion action과 fixture stream 진입만 검증한다.

        await store.send(.hierarchy(.folderExpansionRequested(id: projectsID))) {
            $0.hierarchy.expandedFolderIDs = [projectsID]
            $0.hierarchy.foldersByID[projectsID] = .init(phase: .loading, generation: 1)
        }
        await store.receive(\.delegate.expandRequested)
        await store.finish()
    }
}
