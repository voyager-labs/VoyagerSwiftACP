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
final class ContentAiChatPresentationTests: XCTestCase {
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

    func testAiChatSetupUsesPersistedProviderAvailability() {
        let state = makeState()
        let noProviderSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(
            content: state,
            sessionID: makeSessionID("00000000-0000-0000-0000-000000000001"),
            connectionsFile: .empty(),
        )

        XCTAssertEqual(noProviderSetup.catalogRows, [])
        XCTAssertNil(noProviderSetup.selectedModelHandle)

        let configuredSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(
            content: state,
            sessionID: makeSessionID("00000000-0000-0000-0000-000000000002"),
            connectionsFile: .testFixture(lastUsedProviderId: .anthropic, providers: [
                .testFixture(provider: .openai, authMethod: .apiKey, state: .connected),
                .testFixture(provider: .anthropic, authMethod: .apiKey, state: .connected),
                .testFixture(provider: .chatgptCodex, authMethod: .oauth, state: .connectionFailed),
            ]),
        )

        XCTAssertEqual(configuredSetup.catalogRows.map(\.handle.provider), [.openai, .anthropic])
        XCTAssertEqual(configuredSetup.selectedModelHandle?.provider, .anthropic)
    }

    func testOpenContextualAiChatTapDelegatesToWindowCommandPath() async {
        let selected = makeEntry(name: "Draft.md", fullPath: "/tmp/voyager/Draft.md")
        var initialState = makeState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.entryViewLayout.entryOperations.items = [selected]
        initialState.entryViewLayout.selectedIds = [selected.id]

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerEntitiesEntry.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = VoyagerEntitiesEntry.EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
        }

        await store.send(FileManagerContentAction.view(.openContextualAiChatTapped))

        await store.receive { action in
            guard case .delegate(.openContextualAiChat) = action else { return false }
            return true
        }
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

    private func makeSessionID(_ rawValue: String) -> AiChatSessionID {
        guard let uuid = UUID(uuidString: rawValue) else {
            XCTFail("Invalid UUID fixture: \(rawValue)")
            return AiChatSessionID(rawValue: UUID())
        }
        return AiChatSessionID(rawValue: uuid)
    }
}
