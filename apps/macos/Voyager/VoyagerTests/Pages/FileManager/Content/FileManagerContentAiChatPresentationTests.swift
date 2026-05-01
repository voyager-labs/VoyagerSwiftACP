import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentAiChatPresentationTests: XCTestCase {
    func testCurrentViewSnapshotUsesCanonicalNavigationContext() {
        var state = makeState()
        state.navigation.seedInitialFolderPath("/tmp/voyager")

        let snapshot = FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: state)

        XCTAssertEqual(snapshot.summary, "voyager")
        XCTAssertEqual(snapshot.references.count, 1)
        XCTAssertEqual(snapshot.references.first?.kind, .reference)
        XCTAssertEqual(snapshot.references.first?.identifier, "/tmp/voyager")
        XCTAssertEqual(snapshot.references.first?.title, "voyager")
        XCTAssertEqual(snapshot.items, [])
        XCTAssertEqual(snapshot.attachments, [])
    }

    func testSelectedItemSnapshotIncludesSelectedEntriesAndSelectionMetadata() {
        let selected = makeEntry(name: "Draft.md", fullPath: "/tmp/voyager/Draft.md")
        var state = makeState()
        state.navigation.seedInitialFolderPath("/tmp/voyager")
        state.entryViewLayout.entryOperations.items = [selected]
        state.entryViewLayout.selectedIds = [selected.id]

        let snapshot = FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: state)

        XCTAssertEqual(snapshot.summary, "voyager · 1 selected")
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.kind, .file)
        XCTAssertEqual(snapshot.items.first?.identifier, "/tmp/voyager/Draft.md")
        XCTAssertEqual(snapshot.items.first?.title, "Draft.md")
        XCTAssertEqual(snapshot.items.first?.metadata["selected"], "true")
        XCTAssertEqual(snapshot.items.first?.references.first?.identifier, "/tmp/voyager")
    }

    func testPresentAiChatMountsStoreWithContextWithoutOwningChatSemantics() async {
        let selected = makeEntry(name: "Draft.md", fullPath: "/tmp/voyager/Draft.md")
        var initialState = makeState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.entryViewLayout.entryOperations.items = [selected]
        initialState.entryViewLayout.selectedIds = [selected.id]

        let expectedSessionID = AiChatSessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(
            content: initialState,
            sessionID: expectedSessionID,
        )

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerEntitiesEntry.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = VoyagerEntitiesEntry.EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
        }

        await store.send(FileManagerContentAction.view(.presentAiChat)) {
            $0.isAiChatPresented = true
        }

        await store.receive(\.aiChat) {
            $0.aiChat.sessionID = expectedSessionID
            $0.aiChat.sessionStatus = .idle
            $0.aiChat.currentContext = expectedSetup.currentContext
            $0.aiChat.transcriptHistory = []
            $0.aiChat.draftText = ""
            $0.aiChat.streamDraftText = ""
            $0.aiChat.catalogRows = expectedSetup.catalogRows
            $0.aiChat.selectedModelHandle = expectedSetup.selectedModelHandle
            $0.aiChat.lockedModelHandle = nil
            $0.aiChat.lastExecutionFailure = nil
            $0.aiChat.executionPhase = .idle
        }

        XCTAssertEqual(store.state.aiChat.sessionID, expectedSessionID)
        XCTAssertEqual(store.state.aiChat.currentContext, expectedSetup.currentContext)
        XCTAssertEqual(store.state.aiChat.catalogRows, expectedSetup.catalogRows)
        XCTAssertEqual(store.state.aiChat.selectedModelHandle, expectedSetup.selectedModelHandle)
    }

    private func makeState() -> FileManagerContentState {
        FileManagerContentState()
    }

    private func makeEntry(name: String, fullPath: String) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: "md",
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
