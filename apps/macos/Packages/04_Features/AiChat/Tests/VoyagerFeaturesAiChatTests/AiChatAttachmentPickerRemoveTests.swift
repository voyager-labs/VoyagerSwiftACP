import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatAttachmentPickerRemoveTests: XCTestCase {
    func testRemoveAddedAttachmentRemovesOnlyMatchingAttachment() async {
        let first = makeDraftAttachment(id: "first", filePath: "/tmp/First.txt")
        let second = makeDraftAttachment(id: "second", filePath: "/tmp/Second.txt")
        let third = makeDraftAttachment(id: "third", filePath: "/tmp/Third.txt")

        let store = TestStore(initialState: AiChatFeature.State(
            addedAttachments: [first, second, third]
        )) {
            AiChatFeature()
        }

        await store.send(.removeAddedAttachment(second.id)) {
            $0.addedAttachments = [first, third]
        }
    }

    func testRemoveAddedAttachmentDoesNotTouchCurrentContext() async {
        let summary = makeContextSnapshot(summary: "Pinned context")
        let attachment = makeDraftAttachment(id: "remove-me", filePath: "/tmp/Notes.txt")

        let store = TestStore(initialState: AiChatFeature.State(
            currentContext: summary,
            addedAttachments: [attachment]
        )) {
            AiChatFeature()
        }

        await store.send(.removeAddedAttachment(attachment.id)) {
            $0.addedAttachments = []
        }

        XCTAssertEqual(store.state.currentContext, summary)
    }

    func testRemoveAddedAttachmentUnknownIDIsNoOp() async {
        let attachment = makeDraftAttachment(id: "keep", filePath: "/tmp/Keep.txt")
        let store = TestStore(initialState: AiChatFeature.State(
            currentContext: makeContextSnapshot(summary: "Current context"),
            addedAttachments: [attachment]
        )) {
            AiChatFeature()
        }

        await store.send(.removeAddedAttachment(AiChatAttachmentID(rawValue: "missing")))

        XCTAssertEqual(store.state.addedAttachments, [attachment])
        XCTAssertEqual(store.state.currentContext.summary, "Current context")
    }
}

private func makeDraftAttachment(id: String, filePath: String) -> AiChatAttachmentDraft {
    let url = URL(fileURLWithPath: filePath).standardizedFileURL
    return AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: id),
        source: .file,
        displayTitle: url.lastPathComponent,
        sourceLocation: AiChatAttachmentSourceLocation(
            fileURL: url,
            filePath: url.path(percentEncoded: false)
        )
    )
}
