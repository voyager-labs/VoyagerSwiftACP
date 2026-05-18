import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesAiChat
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
}
