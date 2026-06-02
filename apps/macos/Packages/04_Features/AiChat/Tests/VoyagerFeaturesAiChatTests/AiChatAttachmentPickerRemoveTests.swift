import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW002 spec-owner suite로 이관하지 않은 attachment removal 회귀 테스트.
// matching removal과 unknown id no-op 같은 reducer edge contract를 보존한다.

@MainActor
final class AiChatAttachmentPickerRemoveTests: XCTestCase {
    /// 지정한 attachment id만 제거되고 다른 첨부는 유지되는지 검증
    func testRemoveAddedAttachmentRemovesOnlyMatchingAttachment() async {
        let first = makeDraftAttachment(id: "first", filePath: "/tmp/First.txt")
        let second = makeDraftAttachment(id: "second", filePath: "/tmp/Second.txt")
        let third = makeDraftAttachment(id: "third", filePath: "/tmp/Third.txt")

        let store = TestStore(initialState: AiChatFeature.State(
            addedAttachments: [first, second, third],
        )) {
            AiChatFeature()
        }

        await store.send(.removeAddedAttachment(second.id)) {
            $0.addedAttachments = [first, third]
        }
    }

    /// 존재하지 않는 attachment id 제거 요청이 상태를 변경하지 않는지 검증
    func testRemoveAddedAttachmentUnknownIDIsNoOp() async {
        let attachment = makeDraftAttachment(id: "keep", filePath: "/tmp/Keep.txt")
        let store = TestStore(initialState: AiChatFeature.State(
            currentContext: makeContextSnapshot(summary: "Current context"),
            addedAttachments: [attachment],
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
            filePath: url.path(percentEncoded: false),
        ),
    )
}
