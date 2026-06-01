import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW002 spec-owner suite로 이관하지 않은 attachment picker 회귀 테스트.
// 중복 제거, collection/folder source, current context 정리 같은 저수준 reducer contract를 보존한다.

@MainActor
final class AiChatAttachmentPickerAddTests: XCTestCase {
    /// 동일 경로를 picker로 다시 추가해도 attachment draft가 중복되지 않는지 검증
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
                        filePath: normalizedURL.path(percentEncoded: false),
                    ),
                ),
            ]
        }

        await store.send(.attachmentPickerSelection([duplicateURL]))
        XCTAssertEqual(store.state.addedAttachments.count, 1)
    }

    /// collection과 folder source가 attachment draft로 보존되는지 검증
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
                        filePath: collectionURL.standardizedFileURL.path(percentEncoded: false),
                    ),
                ),
                AiChatAttachmentDraft(
                    id: AiChatAttachmentID(rawValue: folderURL.standardizedFileURL.path(percentEncoded: false)),
                    source: .folder,
                    displayTitle: "Projects",
                    sourceLocation: AiChatAttachmentSourceLocation(
                        fileURL: folderURL.standardizedFileURL,
                        filePath: folderURL.standardizedFileURL.path(percentEncoded: false),
                    ),
                    metadata: ["folderStructureMode": AiChatFolderStructureMode.currentFolderOnly.rawValue],
                ),
            ]
        }
    }

    /// current context와 같은 파일을 picker로 추가할 때 중복 attachment가 생기지 않는지 검증
    func testAttachmentPickerSelectionSkipsDuplicateCurrentContextItem() async {
        let url = URL(fileURLWithPath: "/tmp/Notes.txt")
        let normalizedURL = url.standardizedFileURL
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Desktop · 1 selected",
            references: [makeContextReference(title: "Desktop", path: "/tmp")],
            items: [makeContextItem(title: "Notes.txt", path: normalizedURL.path(percentEncoded: false))],
            attachments: [],
        )

        let store = TestStore(initialState: AiChatFeature.State(currentContext: currentContext)) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([url]))
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertTrue(store.state.addedAttachments.isEmpty)
    }

    /// current collection reference와 같은 collection attachment가 중복되지 않는지 검증
    func testAttachmentPickerSelectionSkipsDuplicateCurrentCollectionReference() async {
        let url = URL(fileURLWithPath: "/tmp/Workspace.voycoll")
        let normalizedURL = url.standardizedFileURL
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Workspace.voycoll",
            references: [
                makeContextReference(
                    title: "Workspace.voycoll",
                    path: normalizedURL.path(percentEncoded: false),
                    metadata: ["route": "collection", "path": normalizedURL.path(percentEncoded: false)],
                ),
            ],
            items: [],
            attachments: [],
        )

        let store = TestStore(initialState: AiChatFeature.State(currentContext: currentContext)) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([url]))
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertTrue(store.state.addedAttachments.isEmpty)
    }

    /// drop으로 추가한 attachment가 current context 변경 이후에도 명시적 첨부로 유지되는지 검증
    func testDroppedAttachmentPersistsWhenCurrentContextSelectionChanges() async {
        let droppedURL = URL(fileURLWithPath: "/tmp/Dropped.txt")
        let nextSelectionURL = URL(fileURLWithPath: "/tmp/Other.txt")
        let normalizedDroppedURL = droppedURL.standardizedFileURL
        let droppedPath = normalizedDroppedURL.path(percentEncoded: false)
        let nextSelectionPath = nextSelectionURL.standardizedFileURL.path(percentEncoded: false)

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.attachmentDropSelection([droppedURL])) {
            $0.addedAttachments = [
                AiChatAttachmentDraft(
                    id: AiChatAttachmentID(rawValue: droppedPath),
                    source: .file,
                    displayTitle: "Dropped.txt",
                    sourceLocation: AiChatAttachmentSourceLocation(
                        fileURL: normalizedDroppedURL,
                        filePath: droppedPath,
                    ),
                ),
            ]
        }
        await store.receive(.delegate(.clearCurrentContextSelection))

        let nextCurrentContext = AiChatCurrentContextSnapshot(
            summary: "Desktop · 1 selected",
            references: [makeContextReference(title: "Desktop", path: "/tmp")],
            items: [makeContextItem(title: "Other.txt", path: nextSelectionPath)],
            attachments: [],
        )
        await store.send(.currentContextChanged(nextCurrentContext)) {
            $0.currentContextFolderStructureModesByCanonicalPath = [
                folderKey(.reference, "/tmp"): .currentFolderOnly,
            ]
            $0.currentContext = makeCurrentContextWithFolderMode(itemTitle: "Other.txt", itemPath: nextSelectionPath)
        }

        XCTAssertEqual(store.state.addedAttachments.map(\.id.rawValue), [droppedPath])
    }

    /// current context가 attachment와 같은 파일로 바뀔 때 기존 attachment 중복이 제거되는지 검증
    func testCurrentContextChangedRemovesExistingAttachmentDuplicate() async {
        let url = URL(fileURLWithPath: "/tmp/Notes.txt")
        let normalizedURL = url.standardizedFileURL
        let attachment = AiChatAttachmentDraft(
            id: AiChatAttachmentID(rawValue: normalizedURL.path(percentEncoded: false)),
            source: .file,
            displayTitle: "Notes.txt",
            sourceLocation: AiChatAttachmentSourceLocation(
                fileURL: normalizedURL,
                filePath: normalizedURL.path(percentEncoded: false),
            ),
        )
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Desktop · 1 selected",
            references: [makeContextReference(title: "Desktop", path: "/tmp")],
            items: [makeContextItem(title: "Notes.txt", path: normalizedURL.path(percentEncoded: false))],
            attachments: [],
        )

        let store = TestStore(initialState: AiChatFeature.State(addedAttachments: [attachment])) {
            AiChatFeature()
        }

        await store.send(.currentContextChanged(currentContext)) {
            $0.currentContextFolderStructureModesByCanonicalPath = [folderKey(.reference, "/tmp"): .currentFolderOnly]
            $0.currentContext = AiChatCurrentContextSnapshot(
                summary: "Desktop",
                references: [
                    makeContextReference(
                        title: "Desktop",
                        path: "/tmp",
                        metadata: [
                            "path": "/tmp",
                            "folderStructureMode": AiChatFolderStructureMode.currentFolderOnly.rawValue,
                        ],
                    ),
                ],
                items: [],
                attachments: [],
            )
        }
    }

    /// current folder context가 추가 attachment와 겹칠 때 중복 folder attachment가 정리되는지 검증
    func testCurrentContextChangedRemovesExistingAttachmentCurrentFolderDuplicate() async {
        let folderURL = URL(filePath: "/tmp/Projects", directoryHint: .isDirectory).standardizedFileURL
        let attachment = AiChatAttachmentDraft(
            id: AiChatAttachmentID(rawValue: folderURL.path(percentEncoded: false)),
            source: .folder,
            displayTitle: "Projects",
            sourceLocation: AiChatAttachmentSourceLocation(
                fileURL: folderURL,
                filePath: folderURL.path(percentEncoded: false),
            ),
        )
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Projects",
            references: [makeContextReference(title: "Projects", path: folderURL.path(percentEncoded: false))],
            items: [],
            attachments: [],
        )

        let store = TestStore(initialState: AiChatFeature.State(addedAttachments: [attachment])) {
            AiChatFeature()
        }

        await store.send(.currentContextChanged(currentContext))
        XCTAssertEqual(store.state.currentContext, .init())
    }

    /// 상위 recursive folder가 선택되면 하위 folder mode 중복이 정리되는지 검증
    func testFolderStructureModeCurrentContextPrunesChildFolderCoveredByRecursiveParent() async {
        let folderURL = URL(filePath: "/tmp/Projects", directoryHint: .isDirectory).standardizedFileURL
        let folderPath = folderURL.path(percentEncoded: false)
        let childPath = folderURL.appending(path: "Feature", directoryHint: .isDirectory)
            .standardizedFileURL
            .path(percentEncoded: false)
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Projects · Feature",
            references: [makeContextReference(title: "Projects", path: folderPath, kind: .folder)],
            items: [makeContextItem(title: "Feature", path: childPath, kind: .folder)],
            attachments: [],
        )

        let store = TestStore(initialState: AiChatFeature.State(currentContext: currentContext)) {
            AiChatFeature()
        }

        await store.send(.folderStructureModeChanged(.currentContext, .includeSubfolders)) {
            $0.currentContextFolderStructureModesByCanonicalPath = [
                folderKey(.reference, folderPath): .includeSubfolders,
            ]
            $0.currentContext = AiChatCurrentContextSnapshot(
                summary: "Projects · Feature",
                references: [
                    makeContextReference(
                        title: "Projects",
                        path: folderPath,
                        kind: .folder,
                        metadata: [
                            "path": folderPath,
                            "folderStructureMode": AiChatFolderStructureMode.includeSubfolders.rawValue,
                        ],
                    ),
                ],
                items: [makeContextItem(title: "Feature", path: childPath, kind: .folder)],
                attachments: [],
            )
        }
        XCTAssertNil(store.state.currentContextFolderStructureModesByCanonicalPath[folderKey(.item, childPath)])
        XCTAssertNil(store.state.currentContext.items.first?.metadata["folderStructureMode"])
    }

    /// folder structure mode 변경이 파일 current context에는 적용되지 않는지 검증
    func testFolderStructureModeCurrentContextIgnoresNonFolderItems() async {
        let filePath = URL(fileURLWithPath: "/tmp/Notes.txt").standardizedFileURL.path(percentEncoded: false)
        let collectionPath = URL(fileURLWithPath: "/tmp/Workspace.voycoll").standardizedFileURL
            .path(percentEncoded: false)
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Mixed files",
            references: [
                makeContextReference(
                    title: "Workspace.voycoll",
                    path: collectionPath,
                    metadata: ["route": "collection", "path": collectionPath],
                ),
            ],
            items: [
                makeContextItem(title: "Notes.txt", path: filePath),
                makeContextItem(
                    title: "Pinned note",
                    path: "note://pinned",
                    kind: .note,
                    metadata: ["path": "note://pinned"],
                ),
            ],
            attachments: [],
        )

        let store = TestStore(initialState: AiChatFeature.State(currentContext: currentContext)) {
            AiChatFeature()
        }

        await store.send(.folderStructureModeChanged(.currentContext, .includeSubfolders))

        XCTAssertTrue(store.state.currentContextFolderStructureModesByCanonicalPath.isEmpty)
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertNil(AiChatStateDisplayModelBuilder(state: store.state).requestContextDisplayModel.currentContext?
            .folderStructureMode)
        XCTAssertEqual(
            AiChatStateDisplayModelBuilder(state: store.state).requestContextDisplayModel.currentContext?
                .supportsFolderStructureMode,
            false,
        )
    }
}

private func makeCurrentContextWithFolderMode(
    itemTitle: String,
    itemPath: String,
) -> AiChatCurrentContextSnapshot {
    AiChatCurrentContextSnapshot(
        summary: "Desktop · 1 selected",
        references: [
            makeContextReference(
                title: "Desktop",
                path: "/tmp",
                metadata: [
                    "path": "/tmp",
                    "folderStructureMode": AiChatFolderStructureMode.currentFolderOnly.rawValue,
                ],
            ),
        ],
        items: [makeContextItem(title: itemTitle, path: itemPath)],
        attachments: [],
    )
}

private func makeContextReference(
    title: String,
    path: String,
    kind: AiChatContextItemKind = .reference,
    metadata: [String: String]? = nil,
) -> AiChatContextReference {
    AiChatContextReference(
        kind: kind,
        identifier: path,
        title: title,
        subtitle: path,
        metadata: metadata ?? ["path": path],
    )
}

private func makeContextItem(
    title: String,
    path: String,
    kind: AiChatContextItemKind = .file,
    metadata: [String: String]? = nil,
) -> AiChatContextItem {
    AiChatContextItem(
        kind: kind,
        identifier: path,
        title: title,
        subtitle: path,
        metadata: metadata ?? ["path": path],
    )
}

private func folderKey(
    _ source: AiChatCurrentContextFolderStructureSource,
    _ path: String,
) -> AiChatCurrentContextFolderStructureKey {
    AiChatCurrentContextFolderStructureKey(
        source: source,
        canonicalPath: URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path(percentEncoded: false),
    )
}
