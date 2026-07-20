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
    func testAiChatDroppedAttachmentClearSelectionDelegateClearsContentSelection() async {
        let selectedEntry = makeEntry(name: "Dropped.md", fullPath: "/Users/test/Documents/Dropped.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [selectedEntry]
        initialState.content.entryViewLayout.selectedIds = [selectedEntry.id]

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
        await store.receive(\.content.entryViewLayout.internal.applyClearSelection) {
            $0.content.entryViewLayout.selectedIds = []
        }
        await store.receive(\.content.entryViewLayout.delegate.selectionChanged)
        await store.receive(\.content.entryViewLayout.entryOperations.lifecycle.syncSelectedEntryIDs)
        await store.receive { action in
            guard case .content(.delegate(.currentContextChanged)) = action else { return false }
            return true
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
