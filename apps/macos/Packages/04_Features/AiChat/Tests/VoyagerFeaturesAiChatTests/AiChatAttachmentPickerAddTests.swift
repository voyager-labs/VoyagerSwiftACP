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

    func testAttachmentPickerSelectionSkipsDuplicateCurrentContextItem() async {
        let url = URL(fileURLWithPath: "/tmp/Notes.txt")
        let normalizedURL = url.standardizedFileURL
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Desktop · 1 selected",
            references: [makeContextReference(title: "Desktop", path: "/tmp")],
            items: [makeContextItem(title: "Notes.txt", path: normalizedURL.path(percentEncoded: false))],
            attachments: []
        )

        let store = TestStore(initialState: AiChatFeature.State(currentContext: currentContext)) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([url]))
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertTrue(store.state.addedAttachments.isEmpty)
    }

    func testAttachmentPickerSelectionSkipsDuplicateCurrentCollectionReference() async {
        let url = URL(fileURLWithPath: "/tmp/Workspace.voycoll")
        let normalizedURL = url.standardizedFileURL
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Workspace.voycoll",
            references: [
                makeContextReference(
                    title: "Workspace.voycoll",
                    path: normalizedURL.path(percentEncoded: false),
                    metadata: ["route": "collection", "path": normalizedURL.path(percentEncoded: false)]
                ),
            ],
            items: [],
            attachments: []
        )

        let store = TestStore(initialState: AiChatFeature.State(currentContext: currentContext)) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([url]))
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertTrue(store.state.addedAttachments.isEmpty)
    }

    func testAttachmentDropSelectionSkipsDuplicateCurrentContextItem() async {
        let url = URL(fileURLWithPath: "/tmp/Dropped.txt")
        let normalizedURL = url.standardizedFileURL
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Desktop · 1 selected",
            references: [makeContextReference(title: "Desktop", path: "/tmp")],
            items: [makeContextItem(title: "Dropped.txt", path: normalizedURL.path(percentEncoded: false))],
            attachments: []
        )

        let store = TestStore(initialState: AiChatFeature.State(currentContext: currentContext)) {
            AiChatFeature()
        }

        await store.send(.attachmentDropSelection([url]))
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertTrue(store.state.addedAttachments.isEmpty)
    }

    func testCurrentContextChangedRemovesExistingAttachmentDuplicate() async {
        let url = URL(fileURLWithPath: "/tmp/Notes.txt")
        let normalizedURL = url.standardizedFileURL
        let attachment = AiChatAttachmentDraft(
            id: AiChatAttachmentID(rawValue: normalizedURL.path(percentEncoded: false)),
            source: .file,
            displayTitle: "Notes.txt",
            sourceLocation: AiChatAttachmentSourceLocation(
                fileURL: normalizedURL,
                filePath: normalizedURL.path(percentEncoded: false)
            )
        )
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Desktop · 1 selected",
            references: [makeContextReference(title: "Desktop", path: "/tmp")],
            items: [makeContextItem(title: "Notes.txt", path: normalizedURL.path(percentEncoded: false))],
            attachments: []
        )

        let store = TestStore(initialState: AiChatFeature.State(addedAttachments: [attachment])) {
            AiChatFeature()
        }

        await store.send(.currentContextChanged(currentContext)) {
            $0.currentContext = AiChatCurrentContextSnapshot(
                summary: "Desktop",
                references: [makeContextReference(title: "Desktop", path: "/tmp")],
                items: [],
                attachments: []
            )
        }
    }

    func testCurrentContextChangedRemovesExistingAttachmentCurrentFolderDuplicate() async {
        let folderURL = URL(filePath: "/tmp/Projects", directoryHint: .isDirectory).standardizedFileURL
        let attachment = AiChatAttachmentDraft(
            id: AiChatAttachmentID(rawValue: folderURL.path(percentEncoded: false)),
            source: .folder,
            displayTitle: "Projects",
            sourceLocation: AiChatAttachmentSourceLocation(
                fileURL: folderURL,
                filePath: folderURL.path(percentEncoded: false)
            )
        )
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Projects",
            references: [makeContextReference(title: "Projects", path: folderURL.path(percentEncoded: false))],
            items: [],
            attachments: []
        )

        let store = TestStore(initialState: AiChatFeature.State(addedAttachments: [attachment])) {
            AiChatFeature()
        }

        await store.send(.currentContextChanged(currentContext))
        XCTAssertEqual(store.state.currentContext, .init())
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


private func makeContextReference(
    title: String,
    path: String,
    metadata: [String: String]? = nil
) -> AiChatContextReference {
    AiChatContextReference(
        kind: .reference,
        identifier: path,
        title: title,
        subtitle: path,
        metadata: metadata ?? ["path": path]
    )
}

private func makeContextItem(title: String, path: String) -> AiChatContextItem {
    AiChatContextItem(
        kind: .file,
        identifier: path,
        title: title,
        subtitle: path,
        metadata: ["path": path]
    )
}
