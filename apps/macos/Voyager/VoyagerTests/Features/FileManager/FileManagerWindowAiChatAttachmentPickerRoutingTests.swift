import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class FileManagerWindowAiChatAttachmentPickerRoutingTests: XCTestCase {
    func testAiChatDroppedAttachmentClearSelectionDelegateClearsContentSelection() async throws {
        let selectedEntry = makeEntry(name: "Dropped.md", fullPath: "/Users/test/Documents/Dropped.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryOperations.items = [selectedEntry]
        initialState.content.entryViewLayout.entries = [selectedEntry]
        initialState.content.entryViewLayout.selectedIds = [selectedEntry.id]
        let activeTabID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.tabContentStates[activeTabID] = initialState.content

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }
        let expectedReference = AiChatContextReference(
            kind: .reference,
            identifier: "/Users/test/Documents",
            title: "Documents",
            subtitle: "/Users/test/Documents",
            metadata: [
                "folderStructureMode": "currentFolderOnly",
                "path": "/Users/test/Documents",
                "route": "folder",
            ],
        )
        let expectedCurrentContext = AiChatCurrentContextSnapshot(
            summary: "Documents",
            references: [expectedReference],
        )
        let expectedFolderStructureKey = AiChatCurrentContextFolderStructureKey(
            source: .reference,
            canonicalPath: "/Users/test/Documents",
        )

        await store.send(.inspector(.aiChat(.delegate(.clearCurrentContextSelection))))
        await store.receive(\.inspector.delegate.clearCurrentContextSelection)
        await store.receive { action in
            guard case let .tabContent(tabID, .entryViewLayout(.internal(.applyClearSelection))) = action else {
                return false
            }
            return tabID == activeTabID
        } assert: {
            $0.content.entryViewLayout.selectedIds = []
            $0.tabContentStates[activeTabID]?.entryViewLayout.selectedIds = []
        }
        await store.receive { action in
            guard case let .tabContent(tabID, .entryViewLayout(.delegate(.selectionChanged))) = action else {
                return false
            }
            return tabID == activeTabID
        }
        await store.receive { action in
            guard case let .tabContent(
                tabID,
                .entryOperations(.lifecycle(.syncSelectedEntryIDs)),
            ) = action else { return false }
            return tabID == activeTabID
        }
        await store.receive { action in
            guard case let .tabContent(tabID, .delegate(.currentContextChanged)) = action else { return false }
            return tabID == activeTabID
        }
        await store.receive(\.inspector.aiChat.currentContextChanged) {
            $0.inspector.aiChat.currentContext = expectedCurrentContext
            $0.inspector.aiChat.currentContextFolderStructureModes = [
                expectedFolderStructureKey: .currentFolderOnly,
            ]
        }
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
            fileExtension: (name as NSString).pathExtension,
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
