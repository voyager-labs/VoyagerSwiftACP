import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class CBW002RequestContextManagementTests: XCTestCase {
    // MARK: - CBW-002-show_request_context

    /// CBW-002-show_request_context: draft request context를 current context와 added attachment로 분리해 표시한다.
    /// 사용자가 요청 전에 볼 수 있는 context chip들이 source별로 분리되고 빈 placeholder가 숨겨지는지 검증합니다.
    /// - 검증 내용: display source, current context title, attachment title/status/removable 상태를 확인합니다.
    /// - 사전 조건: current context에는 선택 파일이 있고 added attachment에는 resolved file과 broken file이 있습니다.
    /// - 기대 결과: draft source가 표시되고 current context와 added attachments는 서로 섞이지 않습니다.
    func testShowRequestContextSeparatesDraftCurrentContextAndAddedAttachments() {
        let state = AiChatFeature.State(
            currentContext: makeCBW002CurrentContext(title: "ProjectPlan.md", path: "/tmp/ProjectPlan.md"),
            addedAttachments: [
                makeCBW002DraftAttachment(
                    id: "notes",
                    title: "Notes.txt",
                    status: .resolved(.resolvedText(text: "Notes", metadata: [:])),
                ),
                makeCBW002DraftAttachment(
                    id: "broken",
                    title: "Broken.txt",
                    status: .resolved(.failure(reason: .brokenReference, metadata: [:])),
                ),
            ],
        )

        let displayModel = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel

        XCTAssertEqual(displayModel.source, .draft)
        XCTAssertEqual(displayModel.currentContext?.title, "ProjectPlan.md")
        XCTAssertEqual(displayModel.addedAttachments.map(\.title), ["Notes.txt", "Broken.txt"])
        XCTAssertEqual(displayModel.addedAttachments.map(\.statusLabel), ["Included", "Failed"])
        XCTAssertTrue(displayModel.addedAttachments.allSatisfy(\.isRemovable))
    }

    /// CBW-002-show_request_context: processing 중에는 live draft가 아니라 locked snapshot을 표시한다.
    /// submit 이후 사용자가 current context나 attachment draft를 바꿔도 현재 요청의 snapshot chip이 고정되는지 검증합니다.
    /// - 검증 내용: processing display source와 locked attachment chip, live-only attachment 제외를 확인합니다.
    /// - 사전 조건: executionPhase는 locked context가 있는 processing 상태이고 live state에는 다른 attachment가 있습니다.
    /// - 기대 결과: request context display는 locked source이며 live draft 변경을 현재 요청에 섞지 않습니다.
    func testShowRequestContextUsesLockedSnapshotWhileProcessing() {
        let state = makeProcessingStateWithLockedContext()

        let displayModel = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel

        XCTAssertEqual(displayModel.source, .locked)
        XCTAssertEqual(displayModel.currentContext?.title, "Locked.md")
        XCTAssertEqual(displayModel.addedAttachments.map(\.title), ["LockedNotes.txt"])
        XCTAssertEqual(displayModel.addedAttachments.map(\.isRemovable), [false])
    }

    // MARK: - CBW-002-add_attachment_from_picker

    /// CBW-002-add_attachment_from_picker: picker 선택은 added attachment draft로 추가한다.
    /// 파일 picker에서 들어온 URL이 current context와 별도의 요청 attachment draft로 보존되는지 검증합니다.
    /// - 검증 내용: attachment id, source, displayTitle, sourceLocation을 확인합니다.
    /// - 사전 조건: attachment draft가 없는 새 chat state에서 파일 URL 하나를 선택합니다.
    /// - 기대 결과: normalized path 기반 file attachment draft가 addedAttachments에 추가됩니다.
    func testAddAttachmentFromPickerCreatesFileDraft() async {
        let url = URL(fileURLWithPath: "/tmp/Notes.txt")
        let normalizedURL = url.standardizedFileURL
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([url])) { state in
            state.addedAttachments = [makeCBW002FileDraft(url: normalizedURL)]
        }
    }

    /// CBW-002-add_attachment_from_picker: picker 선택은 normalized path 기준으로 중복 attachment를 만들지 않는다.
    /// 같은 파일을 서로 다른 URL 표현으로 다시 선택해도 요청 context chip이 하나로 유지되는지 검증합니다.
    /// - 검증 내용: 두 번째 picker selection 이후 added attachment count와 id를 확인합니다.
    /// - 사전 조건: `/tmp/Folder/../Notes.txt`를 먼저 추가한 뒤 `/tmp/Notes.txt`를 다시 선택합니다.
    /// - 기대 결과: normalized path가 같은 attachment는 중복 추가되지 않습니다.
    func testAddAttachmentFromPickerDeduplicatesNormalizedPath() async {
        let originalURL = URL(fileURLWithPath: "/tmp/Folder/../Notes.txt")
        let duplicateURL = URL(fileURLWithPath: "/tmp/Notes.txt")
        let normalizedURL = duplicateURL.standardizedFileURL
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([originalURL])) { state in
            state.addedAttachments = [makeCBW002FileDraft(url: normalizedURL)]
        }

        await store.send(.attachmentPickerSelection([duplicateURL]))
        XCTAssertEqual(store.state.addedAttachments.map(\.id.rawValue), [normalizedURL.path(percentEncoded: false)])
    }

    /// CBW-002-add_attachment_from_picker: picker는 collection 문서와 folder source를 attachment draft로 보존한다.
    /// 파일 외 source가 요청 context attachment로 들어올 때 source type과 folder mode metadata가 유지되는지 검증합니다.
    /// - 검증 내용: collectionDocument, folder source와 folderStructureMode metadata를 확인합니다.
    /// - 사전 조건: `.voycoll` collection 파일과 Projects folder를 picker에서 함께 선택합니다.
    /// - 기대 결과: 두 source가 각각 collection/folder attachment draft로 추가됩니다.
    func testAddAttachmentFromPickerAcceptsCollectionAndFolderSources() async {
        let collectionURL = URL(fileURLWithPath: "/tmp/Workspace.voycoll")
        let folderURL = URL(filePath: "/tmp/Projects", directoryHint: .isDirectory)
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([collectionURL, folderURL])) { state in
            state.addedAttachments = [
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

    /// CBW-002-add_attachment_from_picker: current context와 같은 파일은 picker attachment로 중복하지 않는다.
    /// 이미 live context에 포함된 파일을 사용자가 다시 첨부해도 draft attachment가 생기지 않는지 검증합니다.
    /// - 검증 내용: addedAttachments가 비어 있고 currentContext가 보존되는지 확인합니다.
    /// - 사전 조건: current context가 `/tmp/Notes.txt` 파일을 포함하고 같은 파일을 picker로 선택합니다.
    /// - 기대 결과: current context만 유지되고 request attachment는 추가되지 않습니다.
    func testAddAttachmentFromPickerSkipsDuplicateCurrentContextItem() async {
        let url = URL(fileURLWithPath: "/tmp/Notes.txt")
        let normalizedPath = url.standardizedFileURL.path(percentEncoded: false)
        let currentContext = makeCBW002CurrentContext(title: "Notes.txt", path: normalizedPath)
        let store = TestStore(initialState: AiChatFeature.State(currentContext: currentContext)) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection([url]))
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertTrue(store.state.addedAttachments.isEmpty)
    }

    /// CBW-002-add_attachment_from_picker: current collection reference와 같은 collection attachment를 중복하지 않는다.
    /// collection 기반 current context가 있을 때 같은 `.voycoll` 선택이 별도 attachment를 만들지 않는지 검증합니다.
    /// - 검증 내용: addedAttachments가 비어 있고 collection reference context가 유지되는지 확인합니다.
    /// - 사전 조건: current context reference metadata가 collection route와 path를 가진 상태입니다.
    /// - 기대 결과: 같은 collection file은 request attachment로 중복 추가되지 않습니다.
    func testAddAttachmentFromPickerSkipsDuplicateCurrentCollectionReference() async {
        let url = URL(fileURLWithPath: "/tmp/Workspace.voycoll")
        let normalizedPath = url.standardizedFileURL.path(percentEncoded: false)
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Workspace.voycoll",
            references: [
                makeCBW002ContextReference(
                    title: "Workspace.voycoll",
                    path: normalizedPath,
                    metadata: ["route": "collection", "path": normalizedPath],
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

    /// CBW-002-add_attachment_from_picker: attachment picker button은 host picker 요청 delegate로 이어진다.
    /// reducer가 직접 AppKit picker를 열지 않고 host boundary에 요청을 위임하는지 검증합니다.
    /// - 검증 내용: attachmentPickerTapped 이후 requestAttachmentPicker delegate를 확인합니다.
    /// - 사전 조건: attachment draft가 없는 idle chat state입니다.
    /// - 기대 결과: feature는 delegate만 방출하고 state를 직접 변경하지 않습니다.
    func testAttachmentPickerTappedDelegatesRequestAttachmentPicker() async {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }
        // delegate 방출만 검증하는 boundary test라 unrelated state exhaustivity를 낮춥니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.attachmentPickerTapped)
        await store.receive(.delegate(.requestAttachmentPicker))
    }

    // MARK: - CBW-002-add_attachment_by_drop

    /// CBW-002-add_attachment_by_drop: drag-and-drop attachment는 selection context에서 분리된 attachment로 승격된다.
    /// drop 입력이 current context duplicate라도 명시 attachment로 유지되고 기존 selection clear delegate를 내보내는지 검증합니다.
    /// - 검증 내용: added attachment 생성, current context 정리, clearCurrentContextSelection delegate를 확인합니다.
    /// - 사전 조건: current context가 같은 파일을 선택 중이고 사용자가 동일 파일을 drop합니다.
    /// - 기대 결과: dropped file은 attachment로 남고 current context selection은 clear 요청됩니다.
    func testAddAttachmentByDropPromotesDuplicateCurrentContextItem() async {
        let url = URL(fileURLWithPath: "/tmp/Dropped.txt")
        let normalizedURL = url.standardizedFileURL
        let normalizedPath = normalizedURL.path(percentEncoded: false)
        let folderKey = makeCBW002FolderKey(.reference, "/tmp")
        let store = TestStore(initialState: AiChatFeature.State(
            currentContext: makeCBW002CurrentContext(title: "Dropped.txt", path: normalizedPath),
        )) {
            AiChatFeature()
        }

        await store.send(.attachmentDropSelection([url])) { state in
            state.addedAttachments = [makeCBW002FileDraft(url: normalizedURL)]
            state.currentContextFolderStructureModes = [folderKey: .currentFolderOnly]
            state.currentContext = makeCBW002CurrentContext(
                title: nil,
                path: "/tmp",
                summary: "Desktop",
                mode: .currentFolderOnly,
            )
        }
        await store.receive(.delegate(.clearCurrentContextSelection))
    }

    /// CBW-002-add_attachment_by_drop: drop attachment는 current context 변경 후에도 명시 attachment로 유지된다.
    /// drop으로 추가한 파일이 다음 selection refresh에 흡수되거나 사라지지 않는지 검증합니다.
    /// - 검증 내용: currentContextChanged 이후 added attachment id가 유지되는지 확인합니다.
    /// - 사전 조건: Dropped.txt를 drop한 뒤 current context가 Other.txt로 변경됩니다.
    /// - 기대 결과: drop attachment는 request context에 남고 새 current context folder mode가 적용됩니다.
    func testDroppedAttachmentPersistsWhenCurrentContextSelectionChanges() async {
        let droppedURL = URL(fileURLWithPath: "/tmp/Dropped.txt")
        let nextSelectionURL = URL(fileURLWithPath: "/tmp/Other.txt")
        let normalizedDroppedURL = droppedURL.standardizedFileURL
        let droppedPath = normalizedDroppedURL.path(percentEncoded: false)
        let nextSelectionPath = nextSelectionURL.standardizedFileURL.path(percentEncoded: false)
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.attachmentDropSelection([droppedURL])) { state in
            state.addedAttachments = [makeCBW002FileDraft(url: normalizedDroppedURL)]
        }
        await store.receive(.delegate(.clearCurrentContextSelection))

        let nextCurrentContext = makeCBW002CurrentContext(title: "Other.txt", path: nextSelectionPath)
        await store.send(.currentContextChanged(nextCurrentContext)) { state in
            state.currentContextFolderStructureModes = [
                makeCBW002FolderKey(.reference, "/tmp"): .currentFolderOnly,
            ]
            state.currentContext = makeCBW002CurrentContext(
                title: "Other.txt",
                path: nextSelectionPath,
                summary: "Desktop · 1 selected",
                mode: .currentFolderOnly,
            )
        }

        XCTAssertEqual(store.state.addedAttachments.map(\.id.rawValue), [droppedPath])
    }

    // MARK: - CBW-002-change_context_folder_structure_mode

    /// CBW-002-change_context_folder_structure_mode: current folder mode 변경은 context refresh 이후에도 유지된다.
    /// folder structure mode가 canonical folder key에 저장되어 다음 current context snapshot에도 적용되는지 검증합니다.
    /// - 검증 내용: folderStructureMode map, refreshed current context metadata, display model mode를 확인합니다.
    /// - 사전 조건: current context는 Projects 폴더이고 사용자가 includeSubfolders로 변경합니다.
    /// - 기대 결과: refresh 뒤에도 Projects folder chip은 includeSubfolders mode를 유지합니다.
    func testChangeContextFolderStructureModePersistsAcrossRefresh() async {
        let folderURL = URL(filePath: "/tmp/Projects", directoryHint: .isDirectory).standardizedFileURL
        let folderPath = folderURL.path(percentEncoded: false)
        let folderKey = makeCBW002FolderKey(.reference, folderPath)
        let store = TestStore(initialState: AiChatFeature.State(
            currentContext: makeCBW002FolderContext(summary: "Projects", folderPath: folderPath),
        )) {
            AiChatFeature()
        }

        await store.send(.folderStructureModeChanged(.currentContext, .includeSubfolders)) { state in
            state.currentContextFolderStructureModes = [folderKey: .includeSubfolders]
            state.currentContext = makeCBW002FolderContext(
                summary: "Projects",
                folderPath: folderPath,
                mode: .includeSubfolders,
            )
        }
        await store.send(.currentContextChanged(makeCBW002FolderContext(
            summary: "Projects · 1 selected",
            folderPath: folderPath,
        ))) { state in
            state.currentContext = makeCBW002FolderContext(
                summary: "Projects · 1 selected",
                folderPath: folderPath,
                mode: .includeSubfolders,
            )
        }

        XCTAssertEqual(
            AiChatStateDisplayModelBuilder(state: store.state).requestContextDisplayModel.currentContext?
                .folderStructureMode,
            .includeSubfolders,
        )
    }

    /// CBW-002-change_context_folder_structure_mode: current context 변경은 기존 duplicate attachment를 정리한다.
    /// 새 selection이 이미 추가된 attachment와 같은 파일이면 attachment chip이 중복 표시되지 않는지 검증합니다.
    /// - 검증 내용: currentContextChanged 이후 duplicate attachment 제거와 folder-only context 변환을 확인합니다.
    /// - 사전 조건: Notes.txt attachment가 있고 current context도 같은 파일로 변경됩니다.
    /// - 기대 결과: attachment는 제거되고 current context는 Desktop folder context로 정규화됩니다.
    func testCurrentContextChangedRemovesExistingAttachmentDuplicate() async {
        let url = URL(fileURLWithPath: "/tmp/Notes.txt")
        let normalizedURL = url.standardizedFileURL
        let attachment = makeCBW002FileDraft(url: normalizedURL)
        let currentContext = makeCBW002CurrentContext(
            title: "Notes.txt",
            path: normalizedURL.path(percentEncoded: false),
        )
        let store = TestStore(initialState: AiChatFeature.State(addedAttachments: [attachment])) {
            AiChatFeature()
        }

        await store.send(.currentContextChanged(currentContext)) { state in
            state.currentContextFolderStructureModes = [makeCBW002FolderKey(.reference, "/tmp"): .currentFolderOnly]
            state.currentContext = makeCBW002CurrentContext(
                title: nil,
                path: "/tmp",
                summary: "Desktop",
                mode: .currentFolderOnly,
            )
        }
    }

    /// CBW-002-change_context_folder_structure_mode: current folder context와 같은 folder attachment는 중복 제거된다.
    /// folder attachment가 live folder context로 승격될 때 요청 attachment에 같은 folder가 남지 않는지 검증합니다.
    /// - 검증 내용: currentContextChanged 이후 중복 folder attachment와 context 상태를 확인합니다.
    /// - 사전 조건: Projects folder attachment가 있고 current context가 같은 Projects folder로 변경됩니다.
    /// - 기대 결과: reducer는 중복 folder source를 제거하고 current context를 빈 snapshot으로 정리합니다.
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
        let currentContext = makeCBW002FolderContext(
            summary: "Projects",
            folderPath: folderURL.path(percentEncoded: false),
        )
        let store = TestStore(initialState: AiChatFeature.State(addedAttachments: [attachment])) {
            AiChatFeature()
        }

        await store.send(.currentContextChanged(currentContext))
        XCTAssertEqual(store.state.currentContext, .init())
    }

    /// CBW-002-change_context_folder_structure_mode: recursive parent folder 선택은 child folder mode 중복을 정리한다.
    /// includeSubfolders가 parent reference에 적용되면 child item mode가 남지 않는지 검증합니다.
    /// - 검증 내용: parent folder key만 유지되고 child item key/metadata가 제거되는지 확인합니다.
    /// - 사전 조건: Projects reference와 Feature child folder item이 같은 current context에 있습니다.
    /// - 기대 결과: parent includeSubfolders mode만 유지되어 folder context가 중복 계산되지 않습니다.
    func testFolderStructureModeCurrentContextPrunesChildFolderCoveredByRecursiveParent() async {
        let folderURL = URL(filePath: "/tmp/Projects", directoryHint: .isDirectory).standardizedFileURL
        let folderPath = folderURL.path(percentEncoded: false)
        let childPath = folderURL.appending(path: "Feature", directoryHint: .isDirectory)
            .standardizedFileURL
            .path(percentEncoded: false)
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Projects · Feature",
            references: [makeCBW002ContextReference(title: "Projects", path: folderPath, kind: .folder)],
            items: [makeCBW002ContextItem(title: "Feature", path: childPath, kind: .folder)],
            attachments: [],
        )
        let store = TestStore(initialState: AiChatFeature.State(currentContext: currentContext)) {
            AiChatFeature()
        }

        await store.send(.folderStructureModeChanged(.currentContext, .includeSubfolders)) { state in
            state.currentContextFolderStructureModes = [makeCBW002FolderKey(.reference, folderPath): .includeSubfolders]
            state.currentContext = AiChatCurrentContextSnapshot(
                summary: "Projects · Feature",
                references: [
                    makeCBW002ContextReference(
                        title: "Projects",
                        path: folderPath,
                        kind: .folder,
                        metadata: [
                            "path": folderPath,
                            "folderStructureMode": AiChatFolderStructureMode.includeSubfolders.rawValue,
                        ],
                    ),
                ],
                items: [makeCBW002ContextItem(title: "Feature", path: childPath, kind: .folder)],
                attachments: [],
            )
        }
        XCTAssertNil(store.state.currentContextFolderStructureModes[makeCBW002FolderKey(.item, childPath)])
        XCTAssertNil(store.state.currentContext.items.first?.metadata["folderStructureMode"])
    }

    /// CBW-002-change_context_folder_structure_mode: folder mode 변경은 file/non-folder current context에는 적용되지 않는다.
    /// 파일과 note 중심 context에서 folder-only 제어가 잘못 표시되지 않는지 검증합니다.
    /// - 검증 내용: folder mode map, current context, display model support flag를 확인합니다.
    /// - 사전 조건: current context는 collection reference, file item, note item만 포함합니다.
    /// - 기대 결과: folder structure mode 변경은 no-op이고 display model도 folder mode를 지원하지 않습니다.
    func testFolderStructureModeCurrentContextIgnoresNonFolderItems() async {
        let filePath = URL(fileURLWithPath: "/tmp/Notes.txt").standardizedFileURL.path(percentEncoded: false)
        let collectionPath = URL(fileURLWithPath: "/tmp/Workspace.voycoll").standardizedFileURL
            .path(percentEncoded: false)
        let currentContext = AiChatCurrentContextSnapshot(
            summary: "Mixed files",
            references: [
                makeCBW002ContextReference(
                    title: "Workspace.voycoll",
                    path: collectionPath,
                    metadata: ["route": "collection", "path": collectionPath],
                ),
            ],
            items: [
                makeCBW002ContextItem(title: "Notes.txt", path: filePath),
                makeCBW002ContextItem(
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

        XCTAssertTrue(store.state.currentContextFolderStructureModes.isEmpty)
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertNil(AiChatStateDisplayModelBuilder(state: store.state).requestContextDisplayModel.currentContext?
            .folderStructureMode)
        XCTAssertEqual(
            AiChatStateDisplayModelBuilder(state: store.state).requestContextDisplayModel.currentContext?
                .supportsFolderStructureMode,
            false,
        )
    }

    // MARK: - CBW-002-remove_request_context

    /// CBW-002-remove_request_context: added attachment 제거는 current context를 변경하지 않는다.
    /// 사용자가 명시 추가한 request attachment만 제거하고 live current context는 그대로 유지되는지 검증합니다.
    /// - 검증 내용: addedAttachments 제거와 currentContext 보존을 확인합니다.
    /// - 사전 조건: state에는 current context와 added attachment가 각각 하나씩 있습니다.
    /// - 기대 결과: remove action 후 attachment는 비고 current context는 기존 snapshot과 동일합니다.
    func testRemoveRequestContextRemovesOnlyAddedAttachment() async {
        let currentContext = makeCBW002CurrentContext(title: "Current.md", path: "/tmp/Current.md")
        let attachment = makeCBW002DraftAttachment(id: "notes", title: "Notes.txt", filePath: "/tmp/Notes.txt")
        let store = TestStore(initialState: AiChatFeature.State(
            currentContext: currentContext,
            addedAttachments: [attachment],
        )) {
            AiChatFeature()
        }

        await store.send(.removeAddedAttachment(attachment.id)) { state in
            state.addedAttachments = []
        }
        XCTAssertEqual(store.state.currentContext, currentContext)
    }

    /// CBW-002-remove_request_context: 지정한 attachment id만 제거하고 다른 첨부는 유지한다.
    /// 여러 request attachment가 있을 때 remove action이 matching id에만 적용되는지 검증합니다.
    /// - 검증 내용: first/third attachment 보존과 second attachment 제거를 확인합니다.
    /// - 사전 조건: addedAttachments에 first, second, third가 순서대로 있습니다.
    /// - 기대 결과: second만 제거되고 나머지 attachment 순서는 유지됩니다.
    func testRemoveRequestContextRemovesOnlyMatchingAttachment() async {
        let first = makeCBW002DraftAttachment(id: "first", title: "First.txt", filePath: "/tmp/First.txt")
        let second = makeCBW002DraftAttachment(id: "second", title: "Second.txt", filePath: "/tmp/Second.txt")
        let third = makeCBW002DraftAttachment(id: "third", title: "Third.txt", filePath: "/tmp/Third.txt")
        let store = TestStore(initialState: AiChatFeature.State(addedAttachments: [first, second, third])) {
            AiChatFeature()
        }

        await store.send(.removeAddedAttachment(second.id)) { state in
            state.addedAttachments = [first, third]
        }
    }

    /// CBW-002-remove_request_context: 알 수 없는 attachment id 제거 요청은 no-op이다.
    /// stale UI event나 이미 제거된 chip에서 들어온 remove action이 context를 손상하지 않는지 검증합니다.
    /// - 검증 내용: addedAttachments와 currentContext summary가 변경되지 않는지 확인합니다.
    /// - 사전 조건: keep attachment 하나와 current context snapshot이 있습니다.
    /// - 기대 결과: missing id remove action은 상태를 바꾸지 않습니다.
    func testRemoveRequestContextUnknownIDIsNoOp() async {
        let attachment = makeCBW002DraftAttachment(id: "keep", title: "Keep.txt", filePath: "/tmp/Keep.txt")
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

    // MARK: - CBW-002-capture_request_context_snapshot

    /// CBW-002-capture_request_context_snapshot: submit은 current context와 attachment draft를 locked snapshot으로 고정한다.
    /// 요청 시작 시점의 context snapshot이 provider request에 기록되고 이후 draft 상태와 분리되는지 검증합니다.
    /// - 검증 내용: execution request의 currentContext, addedAttachments, locked parts source를 확인합니다.
    /// - 사전 조건: OpenAI 모델이 선택되어 있고 current context와 파일 attachment가 있는 draft를 submit합니다.
    /// - 기대 결과: provider request는 submit 시점의 context와 attachment snapshot을 포함합니다.
    func testCaptureRequestContextSnapshotLocksContextAndAttachmentOnSubmit() async throws {
        let sandbox = try makeCBW002TemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let fileURL = sandbox.appendingPathComponent("Notes.txt")
        try "Snapshot body".write(to: fileURL, atomically: true, encoding: .utf8)
        let stream = AiChatExecutionStreamDriver()
        let store = makeSnapshotSubmitStore(stream: stream, fileURL: fileURL)
        applyCBW002ObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store)

        let request = try XCTUnwrap(stream.requests.first)
        XCTAssertEqual(request.context.currentContext.summary, "Current selected file")
        XCTAssertEqual(request.context.requestContext.addedAttachments.map(\.displayTitle), ["Notes.txt"])
        XCTAssertEqual(request.context.requestContext.parts.map(\.source), [.attachment, .currentContext])
    }
}

private extension CBW002RequestContextManagementTests {
    func applyCBW002ObservationFocusedExhaustivity(
        to store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
    ) {
        // 사용자에게 보이는 context snapshot과 provider request payload를 중심으로 검증하기 위해 exhaustivity를 낮춥니다.
        store.exhaustivity = .off(showSkippedAssertions: false)
    }

    func makeProcessingStateWithLockedContext() -> AiChatFeature.State {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedContext = AiChatLockedRequestContextSnapshot(
            currentContext: makeCBW002CurrentContext(title: "Locked.md", path: "/tmp/Locked.md"),
            addedAttachments: [makeCBW002LockedAttachment(id: "locked", title: "LockedNotes.txt")],
        )
        let requestContext = makeRequestContext(
            sessionID: AiChatSessionID(rawValue: UUID()),
            requestID: AiChatRequestID(rawValue: UUID()),
            runID: AiChatRunID(rawValue: UUID()),
            model: selectedHandle,
            selectedRow: catalogRows[0],
            promptSummary: "Use locked context",
        ).withRequestContext(lockedContext)
        let request = AiChatRequest(
            context: requestContext,
            messages: [AiChatMessage(role: .user, content: "Use locked context")],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        return AiChatFeature.State(
            sessionStatus: .active,
            currentContext: makeCBW002CurrentContext(title: "LiveOnly.md", path: "/tmp/LiveOnly.md"),
            addedAttachments: [makeCBW002DraftAttachment(id: "live", title: "LiveOnly.txt")],
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .processing(lock),
        )
    }

    func makeSnapshotSubmitStore(
        stream: AiChatExecutionStreamDriver,
        fileURL: URL,
    ) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        return TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111202")),
            sessionStatus: .active,
            currentContext: makeCBW002CurrentContext(
                title: "Current.md",
                path: "/tmp/Current.md",
                summary: "Current selected file",
            ),
            addedAttachments: [makeCBW002FileDraft(url: fileURL.standardizedFileURL)],
            draftText: "Summarize context",
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: selectedHandle,
            executionPhase: .idle,
            providerConnectionSnapshot: .known([.openai]),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_002_200))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: {
                    let providerRecord = makeProviderRecord(
                        provider: .openai,
                        credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
                    )
                    return makeConnectionsFile(providers: [providerRecord])
                },
                save: { .success($0) },
                deleteCredential: { _ in .success(.empty()) },
            )
        }
    }

    func makeCBW002TemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private func makeCBW002CurrentContext(
    title: String?,
    path: String,
    summary: String = "Desktop · 1 selected",
    mode: AiChatFolderStructureMode? = nil,
) -> AiChatCurrentContextSnapshot {
    var referenceMetadata = ["path": "/tmp"]
    if let mode {
        referenceMetadata["folderStructureMode"] = mode.rawValue
    }
    let reference = makeCBW002ContextReference(
        title: "Desktop",
        path: "/tmp",
        kind: .folder,
        metadata: referenceMetadata,
    )
    return AiChatCurrentContextSnapshot(
        summary: summary,
        references: [reference],
        items: title.map { [makeCBW002ContextItem(title: $0, path: path)] } ?? [],
        attachments: [],
    )
}

private func makeCBW002FolderContext(
    summary: String,
    folderPath: String,
    mode: AiChatFolderStructureMode? = nil,
) -> AiChatCurrentContextSnapshot {
    var metadata = ["path": folderPath]
    if let mode {
        metadata["folderStructureMode"] = mode.rawValue
    }
    let reference = makeCBW002ContextReference(
        title: "Projects",
        path: folderPath,
        kind: .folder,
        metadata: metadata,
    )
    return AiChatCurrentContextSnapshot(
        summary: summary,
        references: [reference],
        items: [],
        attachments: [],
    )
}

private func makeCBW002ContextReference(
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

private func makeCBW002ContextItem(
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

private func makeCBW002DraftAttachment(
    id: String,
    title: String,
    filePath: String? = nil,
    status: AiChatAttachmentDraftStatus = .pending,
) -> AiChatAttachmentDraft {
    AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: id),
        source: .file,
        displayTitle: title,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: filePath),
        currentStatus: status,
    )
}

private func makeCBW002FileDraft(url: URL) -> AiChatAttachmentDraft {
    AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: url.path(percentEncoded: false)),
        source: .file,
        displayTitle: url.lastPathComponent,
        sourceLocation: AiChatAttachmentSourceLocation(fileURL: url, filePath: url.path(percentEncoded: false)),
    )
}

private func makeCBW002LockedAttachment(
    id: String,
    title: String,
) -> AiChatAttachmentSnapshot {
    AiChatAttachmentSnapshot(
        id: AiChatAttachmentID(rawValue: id),
        source: .file,
        displayTitle: title,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/\(title)"),
        resolutionResult: .resolvedText(text: "Locked text", metadata: [:]),
    )
}

private func makeCBW002FolderKey(
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

private extension AiChatRequestContextSnapshot {
    func withRequestContext(_ requestContext: AiChatLockedRequestContextSnapshot) -> AiChatRequestContextSnapshot {
        AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            provider: provider,
            model: model,
            selectedModel: selectedModel,
            selectedModelRow: selectedModelRow,
            selectedThinking: selectedThinking,
            sessionStatus: sessionStatus,
            currentContext: requestContext.currentContext,
            requestContext: requestContext,
            promptSummary: promptSummary,
            submittedAtMs: submittedAtMs,
        )
    }
}
