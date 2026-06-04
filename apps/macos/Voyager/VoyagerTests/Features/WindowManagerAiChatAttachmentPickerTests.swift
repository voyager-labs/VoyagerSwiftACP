import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class WindowManagerAiChatAttachmentPickerTests: XCTestCase {
    func testRequestAttachmentPickerFeedsSelectionBackIntoAiChat() async {
        let windowID = UUID()
        let pickedURL = URL(fileURLWithPath: "/tmp/Workspace.voycoll")
        let normalizedURL = pickedURL.standardizedFileURL

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: windowID, window: .makeInitial(path: "/tmp")),
        ]

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.attachmentPickerClient.pickAttachments = { [pickedURL] }
        }
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: windowID,
            action: .window(.delegate(.requestAttachmentPicker)),
        )))
        await store.finish()

        XCTAssertEqual(
            store.state.windows[id: windowID]?.window.inspector.aiChat.addedAttachments,
            [
                AiChatAttachmentDraft(
                    id: AiChatAttachmentID(rawValue: normalizedURL.path(percentEncoded: false)),
                    source: .collectionDocument,
                    displayTitle: "Workspace.voycoll",
                    sourceLocation: AiChatAttachmentSourceLocation(
                        fileURL: normalizedURL,
                        filePath: normalizedURL.path(percentEncoded: false),
                    ),
                ),
            ],
        )
    }
}
