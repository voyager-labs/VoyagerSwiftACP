import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class FileManagerInspectorAiChatAttachmentPickerRoutingTests: XCTestCase {
    func testAiChatRequestAttachmentPickerDelegateRoutesToInspectorDelegate() async {
        let store = TestStore(initialState: FileManagerInspectorFeature.State()) {
            FileManagerInspectorFeature()
        }

        await store.send(.aiChat(.delegate(.requestAttachmentPicker)))
        await store.receive(\.delegate.requestAttachmentPicker)
    }

    func testAiChatClearCurrentContextSelectionDelegateRoutesToInspectorDelegate() async {
        let store = TestStore(initialState: FileManagerInspectorFeature.State()) {
            FileManagerInspectorFeature()
        }

        await store.send(.aiChat(.delegate(.clearCurrentContextSelection)))
        await store.receive(\.delegate.clearCurrentContextSelection)
    }
}
