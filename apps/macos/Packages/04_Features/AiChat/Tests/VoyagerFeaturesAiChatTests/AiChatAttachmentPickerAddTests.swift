import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatAttachmentPickerAddTests: XCTestCase {
    func testAttachmentPickerSelectionAddsAttachmentDraft() async {
        let url = URL(fileURLWithPath: "/tmp/Notes.txt")
        let normalizedURL = url.standardizedFileURL

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([url])) {
            $0.addedAttachments = [
                AiChatAttachmentDraft(
                    id: AiChatAttachmentID(rawValue: normalizedURL.path(percentEncoded: false)),
                    source: .file,
                    displayTitle: "Notes.txt",
                    sourceLocation: AiChatAttachmentSourceLocation(
                        fileURL: normalizedURL,
                        filePath: normalizedURL.path(percentEncoded: false)
                    )
                )
            ]
        }
    }

    func testAttachmentPickerSelectionDeduplicatesNormalizedPath() async {
        let originalURL = URL(fileURLWithPath: "/tmp/Folder/../Notes.txt")
        let duplicateURL = URL(fileURLWithPath: "/tmp/Notes.txt")
        let normalizedURL = duplicateURL.standardizedFileURL

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([originalURL])) {
            $0.addedAttachments = [
                AiChatAttachmentDraft(
                    id: AiChatAttachmentID(rawValue: normalizedURL.path(percentEncoded: false)),
                    source: .file,
                    displayTitle: "Notes.txt",
                    sourceLocation: AiChatAttachmentSourceLocation(
                        fileURL: normalizedURL,
                        filePath: normalizedURL.path(percentEncoded: false)
                    )
                )
            ]
        }

        await store.send(.attachmentPickerSelection([duplicateURL]))
        XCTAssertEqual(store.state.addedAttachments.count, 1)
    }

    func testAttachmentPickerSelectionAcceptsCollectionAndFolderSources() async {
        let collectionURL = URL(fileURLWithPath: "/tmp/Workspace.voycoll")
        let folderURL = URL(filePath: "/tmp/Projects", directoryHint: .isDirectory)

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([collectionURL, folderURL])) {
            $0.addedAttachments = [
                AiChatAttachmentDraft(
                    id: AiChatAttachmentID(rawValue: collectionURL.standardizedFileURL.path(percentEncoded: false)),
                    source: .collectionDocument,
                    displayTitle: "Workspace.voycoll",
                    sourceLocation: AiChatAttachmentSourceLocation(
                        fileURL: collectionURL.standardizedFileURL,
                        filePath: collectionURL.standardizedFileURL.path(percentEncoded: false)
                    )
                ),
                AiChatAttachmentDraft(
                    id: AiChatAttachmentID(rawValue: folderURL.standardizedFileURL.path(percentEncoded: false)),
                    source: .folder,
                    displayTitle: "Projects",
                    sourceLocation: AiChatAttachmentSourceLocation(
                        fileURL: folderURL.standardizedFileURL,
                        filePath: folderURL.standardizedFileURL.path(percentEncoded: false)
                    )
                ),
            ]
        }
    }

    func testAttachmentDropSelectionAddsDraftAndRequestsContextSelectionClear() async {
        let url = URL(fileURLWithPath: "/tmp/Dropped.txt")
        let normalizedURL = url.standardizedFileURL

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.attachmentDropSelection([url])) {
            $0.addedAttachments = [
                AiChatAttachmentDraft(
                    id: AiChatAttachmentID(rawValue: normalizedURL.path(percentEncoded: false)),
                    source: .file,
                    displayTitle: "Dropped.txt",
                    sourceLocation: AiChatAttachmentSourceLocation(
                        fileURL: normalizedURL,
                        filePath: normalizedURL.path(percentEncoded: false)
                    )
                )
            ]
        }
        await store.receive(.delegate(.clearCurrentContextSelection))
    }
}
