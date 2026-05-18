import ComposableArchitecture
import Foundation
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatAttachmentPickerDelegateTests: XCTestCase {
    func testAttachmentPickerTappedDelegatesRequestAttachmentPicker() async {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.attachmentPickerTapped)
        await store.receive(.delegate(.requestAttachmentPicker))
    }
}
