import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class FileManagerWindowAiChatAttachmentPickerRoutingTests: XCTestCase {
    func testAiChatRequestAttachmentPickerDelegateRoutesToWindowDelegate() async {
        let store = TestStore(initialState: FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")) {
            FileManagerFeature()
        }

        await store.send(.inspector(.aiChat(.delegate(.requestAttachmentPicker))))
        await store.receive(\.inspector.delegate.requestAttachmentPicker)
        await store.receive(\.delegate.requestAttachmentPicker)
    }

    func testAiChatDroppedAttachmentClearSelectionDelegateClearsContentSelection() async {
        let selectedEntry = makeEntry(name: "Dropped.md", fullPath: "/Users/test/Documents/Dropped.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [selectedEntry]
        initialState.content.entryViewLayout.selectedIds = [selectedEntry.id]

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.inspector(.aiChat(.delegate(.clearCurrentContextSelection))))
        await store.receive(\.inspector.delegate.clearCurrentContextSelection)
        await store.receive(\.content.entryViewLayout.delegate.selectionChanged) {
            $0.content.entryViewLayout.selectedIds = []
        }
        await store.receive { action in
            guard case .content(.delegate(.currentContextChanged)) = action else { return false }
            return true
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
