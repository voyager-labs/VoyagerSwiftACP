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
    func testAttachmentPickerCompletionKeepsOriginSessionAcrossWindowRouting() async throws {
        let windowID = makeUUID("19191919-2222-3333-4444-000000000635")
        let sessionA = AiChatSessionID(rawValue: makeUUID("20202020-2222-3333-4444-000000000635"))
        let sessionB = AiChatSessionID(rawValue: makeUUID("21212121-2222-3333-4444-000000000635"))
        let pickerStream = AsyncStream<[URL]>.makeStream()
        let selectedURL = URL(fileURLWithPath: "/tmp/A-window-picker.txt")
        var windowState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        windowState.inspector.aiChat = AiChatFeature.State(
            sessionID: sessionA,
            sessionStatus: .active,
        )
        var initialState = WindowManagerFeature.State()
        initialState.windows = [WindowSessionState(id: windowID, window: windowState)]
        initialState.focusedWindowID = windowID
        let setupB = AiChatSetupState(
            restoreSessionID: nil,
            sessionID: sessionB,
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "B draft",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.attachmentPickerClient.pickAttachments = {
                await pickerStream.stream.first(where: { _ in true }) ?? []
            }
        }
        // store.exhaustivity = .off: host origin propagation과 B attachment 불변성만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.windows(.element(
            id: windowID,
            action: .window(.delegate(.requestAttachmentPicker(sessionA))),
        )))
        await store.send(.windows(.element(
            id: windowID,
            action: .window(.inspector(.aiChat(.setup(setupB)))),
        )))
        pickerStream.continuation.yield([selectedURL])
        pickerStream.continuation.finish()
        await store.receive { action in
            guard case let .windows(.element(
                id: receivedWindowID,
                action: .window(.inspector(.aiChat(.attachmentPickerSelection(originSessionID, urls)))),
            )) = action
            else { return false }
            return receivedWindowID == windowID && originSessionID == sessionA && urls == [selectedURL]
        }

        let aiChat = try XCTUnwrap(store.state.windows[id: windowID]?.window.inspector.aiChat)
        XCTAssertEqual(aiChat.sessionID, sessionB)
        XCTAssertEqual(aiChat.draftText, "B draft")
        XCTAssertTrue(aiChat.addedAttachments.isEmpty)
    }

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

    private func makeUUID(_ rawValue: String) -> UUID {
        guard let value = UUID(uuidString: rawValue) else {
            XCTFail("Invalid UUID fixture: \(rawValue)")
            return UUID()
        }
        return value
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
