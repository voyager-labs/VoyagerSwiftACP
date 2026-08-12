import AppKit
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
            sessionID: makeCBW002AttachmentSessionID(),
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

    /// CBW-002-show_request_context: processing 중 locked snapshot과 live next context를 분리해 표시한다.
    /// submit 이후 current response chip은 고정하고 다음 메시지의 current context와 attachment는 별도 편집면으로 유지하는지 검증합니다.
    /// - 검증 내용: locked current-response section과 draft root section의 chip/removable 상태를 확인합니다.
    /// - 사전 조건: executionPhase는 Locked.md context로 processing 중이고 live state에는 LiveOnly.md attachment가 있습니다.
    /// - 기대 결과: current response는 non-removable locked 값이고 next message는 removable live 값입니다.
    func testShowRequestContextUsesLockedSnapshotWhileProcessing() throws {
        let state = makeProcessingStateWithLockedContext()

        let displayModel = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel
        let currentResponse = try XCTUnwrap(displayModel.currentResponse)

        XCTAssertEqual(currentResponse.source, .locked)
        XCTAssertEqual(currentResponse.currentContext?.title, "Locked.md")
        XCTAssertEqual(currentResponse.addedAttachments.map(\.title), ["LockedNotes.txt"])
        XCTAssertEqual(currentResponse.addedAttachments.map(\.isRemovable), [false])
        XCTAssertEqual(displayModel.source, .draft)
        XCTAssertEqual(displayModel.currentContext?.title, "LiveOnly.md")
        XCTAssertEqual(displayModel.addedAttachments.map(\.title), ["LiveOnly.txt"])
        XCTAssertEqual(displayModel.addedAttachments.map(\.isRemovable), [true])
    }

    /// CBW-002-show_request_context: processing 중 locked 응답 context와 editable next context를 동시에 투영한다.
    /// 현재 응답 snapshot을 고정한 채 사용자가 다음 메시지의 current context와 attachment를 편집할 수 있는지 검증합니다.
    /// - 검증 내용: root draft projection의 live current context, removable next attachment, processing lock 불변성을 확인합니다.
    /// - 사전 조건: processing lock에는 Locked.md가 있고 live state에는 LiveOnly.md와 LiveOnly.txt가 있습니다.
    /// - 기대 결과: editable projection은 live 값을 노출하고 active lock은 원 locked context를 그대로 유지합니다.
    func testShowRequestContextProjectsEditableNextContextDuringProcessing() {
        let state = makeProcessingStateWithLockedContext()
        let originalLock = state.executionPhase.lock

        let displayModel = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel

        XCTAssertEqual(displayModel.source, .draft)
        XCTAssertEqual(displayModel.currentContext?.title, "LiveOnly.md")
        XCTAssertEqual(displayModel.addedAttachments.map(\.title), ["LiveOnly.txt"])
        XCTAssertTrue(displayModel.addedAttachments.allSatisfy(\.isRemovable))
        XCTAssertEqual(displayModel.currentResponse?.source, .locked)
        XCTAssertEqual(displayModel.currentResponse?.currentContext?.title, "Locked.md")
        XCTAssertEqual(displayModel.currentResponse?.addedAttachments.map(\.title), ["LockedNotes.txt"])
        XCTAssertEqual(displayModel.currentResponse?.addedAttachments.allSatisfy { !$0.isRemovable }, true)
        XCTAssertEqual(state.executionPhase.lock, originalLock)
    }

    /// CBW-002-show_request_context: processing 중 next context는 add/remove/drop/current-context/folder mode를 편집한다.
    /// 현재 response lock을 유지한 채 다음 메시지 context의 모든 composer 경로가 기존 live state만 갱신하는지 검증합니다.
    /// - 검증 내용: picker/drop attachment 추가, 제거, current context 변경, folder mode 변경과 lock 불변성을 확인합니다.
    /// - 사전 조건: Locked.md request가 processing 중이고 live next context에는 LiveOnly.txt attachment가 있습니다.
    /// - 기대 결과: next projection만 편집되고 active request context/request/model identity는 원 lock과 동일합니다.
    func testShowRequestContextEditsAllNextContextControlsDuringProcessing() async {
        let initialState = makeProcessingStateWithLockedContext()
        let originalLock = initialState.executionPhase.lock
        guard let originSessionID = initialState.sessionID else {
            return XCTFail("Expected processing session owner")
        }
        let pickerURL = URL(fileURLWithPath: "/tmp/NextPicker.txt")
        let dropURL = URL(fileURLWithPath: "/tmp/NextDrop.txt")
        let nextFolderContext = makeCBW002FolderContext(
            summary: "Next folder",
            folderPath: "/tmp/NextFolder",
        )
        let store = TestStore(initialState: initialState) {
            AiChatFeature()
        }
        // store.exhaustivity = .off: processing lock 불변성과 next context 결과만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.attachmentPickerSelection(originSessionID, [pickerURL]))
        await store.send(.attachmentDropSelection(originSessionID, [dropURL]))
        await store.receive(.delegate(.clearCurrentContextSelection))
        await store.send(.removeAddedAttachment(AiChatAttachmentID(rawValue: "live")))
        await store.send(.currentContextChanged(nextFolderContext))
        await store.send(.folderStructureModeChanged(.currentContext, .includeSubfolders))

        let displayModel = AiChatStateDisplayModelBuilder(state: store.state).requestContextDisplayModel
        XCTAssertEqual(displayModel.currentContext?.title, "Next folder")
        XCTAssertEqual(displayModel.currentContext?.folderStructureMode, .includeSubfolders)
        XCTAssertEqual(Set(displayModel.addedAttachments.map(\.title)), ["NextPicker.txt", "NextDrop.txt"])
        XCTAssertTrue(displayModel.addedAttachments.allSatisfy(\.isRemovable))
        XCTAssertEqual(displayModel.currentResponse?.currentContext?.title, "Locked.md")
        XCTAssertEqual(displayModel.currentResponse?.addedAttachments.map(\.title), ["LockedNotes.txt"])
        XCTAssertEqual(store.state.executionPhase.lock, originalLock)
    }

    /// CBW-002-add_attachment_from_picker: 다른 session으로 전환된 뒤 도착한 picker/drop 결과를 무시한다.
    /// 비동기 첨부 결과가 시작 session을 벗어나 현재 session의 draft에 local file을 추가하지 않는지 검증합니다.
    /// - 검증 내용: picker delegate 시작 owner와 stale picker/drop result 이후 B attachment 불변성을 확인합니다.
    /// - 사전 조건: session A에서 첨부 선택을 시작한 뒤 결과가 오기 전에 session B setup을 적용합니다.
    /// - 기대 결과: A origin 결과는 B의 attachments, current context, new-chat preparation provenance를 변경하지 않습니다.
    func testAttachmentResultsFromPreviousSessionDoNotMutateCurrentDraftOrPreparationProvenance() async {
        let catalogRows = makeCatalogRows()
        let models = makeProviderModels()
        let sessionA = AiChatSessionID(rawValue: makeUUID("15151515-2222-3333-4444-000000000635"))
        let sessionB = AiChatSessionID(rawValue: makeUUID("16161616-2222-3333-4444-000000000635"))
        let setupB = AiChatSetupState(
            restoreSessionID: nil,
            sessionID: sessionB,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "B context"),
            transcriptHistory: [],
            draftText: "B draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )
        let pickerStore = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionA,
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
        )) {
            AiChatFeature()
        }
        // store.exhaustivity = .off: async attachment owner와 B draft 불변성만 선별 검증합니다.
        pickerStore.exhaustivity = .off(showSkippedAssertions: false)

        await pickerStore.send(.attachmentPickerTapped)
        await pickerStore.receive(.delegate(.requestAttachmentPicker(sessionA)))
        await pickerStore.send(.setup(setupB))
        let preparationProvenance = pickerStore.state.newChatPreparationProvenance
        await pickerStore.send(.attachmentPickerSelection(sessionA, [URL(fileURLWithPath: "/tmp/A-picker.txt")]))

        XCTAssertEqual(pickerStore.state.sessionID, sessionB)
        XCTAssertEqual(pickerStore.state.draftText, "B draft")
        XCTAssertTrue(pickerStore.state.addedAttachments.isEmpty)
        XCTAssertEqual(pickerStore.state.currentContext.summary, "B context")
        XCTAssertEqual(pickerStore.state.newChatPreparationProvenance, preparationProvenance)

        let dropStore = TestStore(initialState: pickerStore.state) {
            AiChatFeature()
        }
        // store.exhaustivity = .off: stale drop result가 B state와 preparation provenance를 변경하지 않는지 검증합니다.
        dropStore.exhaustivity = .off(showSkippedAssertions: false)
        let staleDropProvider = AiChatAttachmentDropProvider(provider: NSItemProvider())
        await dropStore.send(.attachmentDrop(sessionA, [staleDropProvider]))
        XCTAssertEqual(dropStore.state.newChatPreparationProvenance, preparationProvenance)

        await dropStore.send(.attachmentDropSelection(sessionA, [URL(fileURLWithPath: "/tmp/A-drop.txt")]))

        XCTAssertTrue(dropStore.state.addedAttachments.isEmpty)
        XCTAssertEqual(dropStore.state.currentContext.summary, "B context")
        XCTAssertEqual(dropStore.state.newChatPreparationProvenance, preparationProvenance)
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
        let store = TestStore(initialState: AiChatFeature.State(sessionID: makeCBW002AttachmentSessionID())) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection(makeCBW002AttachmentSessionID(), [url])) { state in
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
        let store = TestStore(initialState: AiChatFeature.State(sessionID: makeCBW002AttachmentSessionID())) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection(makeCBW002AttachmentSessionID(), [originalURL])) { state in
            state.addedAttachments = [makeCBW002FileDraft(url: normalizedURL)]
        }

        await store.send(.attachmentPickerSelection(makeCBW002AttachmentSessionID(), [duplicateURL]))
        XCTAssertEqual(store.state.addedAttachments.map(\.id.rawValue), [normalizedURL.path(percentEncoded: false)])
    }

    /// CBW-002-add_attachment_from_picker: picker는 collection 문서와 folder source를 attachment draft로 보존한다.
    /// 파일 외 source가 요청 context attachment로 들어올 때 source type과 folder mode metadata가 유지되는지 검증합니다.
    /// - 검증 내용: collectionDocument, folder source와 folderStructureMode metadata를 확인합니다.
    /// - 사전 조건: `.voycoll` collection 파일과 Projects folder를 picker에서 함께 선택합니다.
    /// - 기대 결과: 두 source가 각각 collection/folder attachment draft로 추가됩니다.
    func testAddAttachmentFromPickerAcceptsCollectionAndFolderSources() async throws {
        let collectionURL = URL(fileURLWithPath: "/tmp/Workspace.voycoll")
        let sandbox = try makeCBW002TemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let projectsURL = sandbox.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: false)
        let folderURL = projectsURL
        let store = TestStore(initialState: AiChatFeature.State(sessionID: makeCBW002AttachmentSessionID())) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection(
            makeCBW002AttachmentSessionID(),
            [collectionURL, folderURL],
        )) { state in
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
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: makeCBW002AttachmentSessionID(),
            currentContext: currentContext,
        )) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection(makeCBW002AttachmentSessionID(), [url]))
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
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: makeCBW002AttachmentSessionID(),
            currentContext: currentContext,
        )) {
            AiChatFeature()
        }

        await store.send(.attachmentPickerSelection(makeCBW002AttachmentSessionID(), [url]))
        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertTrue(store.state.addedAttachments.isEmpty)
    }

    /// CBW-002-add_attachment_from_picker: attachment picker button은 host picker 요청 delegate로 이어진다.
    /// reducer가 직접 AppKit picker를 열지 않고 host boundary에 요청을 위임하는지 검증합니다.
    /// - 검증 내용: attachmentPickerTapped 이후 requestAttachmentPicker delegate를 확인합니다.
    /// - 사전 조건: attachment draft가 없는 idle chat state입니다.
    /// - 기대 결과: feature는 delegate만 방출하고 state를 직접 변경하지 않습니다.
    func testAttachmentPickerTappedDelegatesRequestAttachmentPicker() async {
        let store = TestStore(initialState: AiChatFeature.State(sessionID: makeCBW002AttachmentSessionID())) {
            AiChatFeature()
        }
        // delegate 방출만 검증하는 boundary test라 unrelated state exhaustivity를 낮춥니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.attachmentPickerTapped)
        await store.receive(.delegate(.requestAttachmentPicker(makeCBW002AttachmentSessionID())))
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
            sessionID: makeCBW002AttachmentSessionID(),
            currentContext: makeCBW002CurrentContext(title: "Dropped.txt", path: normalizedPath),
        )) {
            AiChatFeature()
        }

        await store.send(.attachmentDropSelection(makeCBW002AttachmentSessionID(), [url])) { state in
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
        let store = TestStore(initialState: AiChatFeature.State(sessionID: makeCBW002AttachmentSessionID())) {
            AiChatFeature()
        }

        await store.send(.attachmentDropSelection(makeCBW002AttachmentSessionID(), [droppedURL])) { state in
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

    // MARK: - CBW-002-show_request_context

    /// CBW-002-show_request_context: Current Context Attachment Uses Attachment Icon Instead Of Folder Route Icon
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testCurrentContextAttachmentUsesAttachmentIconInsteadOfFolderRouteIcon() {
        let state = AiChatFeature.State(
            currentContext: makeImageAttachmentCurrentContext(),
            addedAttachments: [],
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "Screenshot.png")
        XCTAssertEqual(currentContext?.iconSystemName, "paperclip")
        XCTAssertNil(currentContext?.iconFilePath)
        XCTAssertNil(currentContext?.folderStructureMode)
        XCTAssertEqual(currentContext?.supportsFolderStructureMode, true)
    }

    /// CBW-002-show_request_context: Locked Current Context Selected File Does Not Fallback To Folder Reference Icon
    /// Path
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testLockedCurrentContextSelectedFileDoesNotFallbackToFolderReferenceIconPath() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedRequestContext = makeLockedSelectedImageFileRequestContext()
        let lock = makeImageAttachmentRequestLock(
            context: lockedRequestContext,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
        )
        let state = AiChatFeature.State(
            sessionID: lock.context.sessionID,
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .processing(lock),
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state)
            .requestContextDisplayModel.currentResponse?.currentContext

        XCTAssertEqual(currentContext?.title, "SCR-20260528-suth.png")
        XCTAssertEqual(currentContext?.iconSystemName, "doc")
        XCTAssertNil(currentContext?.iconFilePath)
        XCTAssertEqual(currentContext?.supportsFolderStructureMode, true)
    }

    /// CBW-002-show_request_context: Locked Current Context Attachment Keeps Attachment Icon During Processing
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testLockedCurrentContextAttachmentKeepsAttachmentIconDuringProcessing() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedRequestContext = makeLockedImageAttachmentRequestContext()
        let lock = makeImageAttachmentRequestLock(
            context: lockedRequestContext,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
        )
        let state = AiChatFeature.State(
            sessionID: lock.context.sessionID,
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .processing(lock),
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state)
            .requestContextDisplayModel.currentResponse?.currentContext

        XCTAssertEqual(currentContext?.title, "Screenshot.png")
        XCTAssertEqual(currentContext?.iconSystemName, "paperclip")
        XCTAssertNil(currentContext?.iconFilePath)
        XCTAssertNil(currentContext?.folderStructureMode)
        XCTAssertEqual(currentContext?.supportsFolderStructureMode, true)
    }

    // MARK: - CBW-002-show_request_context

    /// CBW-002-show_request_context: Request Context Display Model Separates Groups And Hides Empty Placeholder
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testRequestContextDisplayModelSeparatesGroupsAndHidesEmptyPlaceholder() {
        let emptyState = AiChatFeature.State(currentContext: .init(), addedAttachments: [])
        XCTAssertTrue(AiChatStateDisplayModelBuilder(state: emptyState).requestContextDisplayModel.isEmpty)
        XCTAssertNil(AiChatStateDisplayModelBuilder(state: emptyState).requestContextDisplayModel.currentContext)
        XCTAssertTrue(AiChatStateDisplayModelBuilder(state: emptyState).requestContextDisplayModel.addedAttachments
            .isEmpty)

        let displayModel = AiChatStateDisplayModelBuilder(state: makeLiveStateForGroupSeparation())
            .requestContextDisplayModel
        assertDraftDisplayModelGroupSeparation(displayModel)

        let multiSelectState = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Documents",
                references: [makeContextReference(title: "Documents")],
                items: [
                    makeContextItem(title: "One.txt"),
                    makeContextItem(title: "Two.txt"),
                    makeContextItem(title: "Three.txt"),
                ],
            ),
            addedAttachments: [],
        )
        XCTAssertEqual(
            AiChatStateDisplayModelBuilder(state: multiSelectState).requestContextDisplayModel.currentContext?.title,
            "3 Selected",
        )
    }

    /// CBW-002-show_request_context: Current Folder Context Uses Finder Folder Icon Path
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testCurrentFolderContextUsesFinderFolderIconPath() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Desktop",
                references: [
                    makeContextReference(
                        title: "Desktop",
                        metadata: ["route": "folder", "path": "/Users/test/Desktop"],
                    ),
                ],
                items: [],
                attachments: [],
            ),
            addedAttachments: [],
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext
        let currentContextTooltip = aiChatRequestContextTooltipText(
            sourceLabel: "Current context",
            destinationLabel: "ChatGPT Codex",
            statusLabel: aiChatCurrentContextStatusLabel(for: state.currentContext, destinationProvider: .chatgptCodex),
            statusDetail: aiChatCurrentContextStatusDetail(
                for: state.currentContext,
                destinationProvider: .chatgptCodex,
            ),
        )

        XCTAssertEqual(currentContext?.title, "Desktop")
        XCTAssertEqual(currentContext?.iconFilePath, "/Users/test/Desktop")
        XCTAssertTrue(currentContextTooltip.contains("Source: Current context"))
        XCTAssertTrue(currentContextTooltip.contains("Destination: ChatGPT Codex"))
        XCTAssertTrue(currentContextTooltip.contains("Status: Reference only"))
        XCTAssertTrue(currentContextTooltip.contains("contents not included"))
    }

    /// CBW-002-show_request_context: Locked Current Context Chip Uses Resolved Folder Metadata During Processing
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testLockedCurrentContextChipUsesResolvedFolderMetadataDuringProcessing() {
        let catalogRows = makeCatalogRows()
        let (_, currentContext) = makeLockedFolderProcessingState(catalogRows: catalogRows)

        XCTAssertEqual(currentContext?.title, "Desktop")
        XCTAssertEqual(currentContext?.iconSystemName, "folder")
        XCTAssertEqual(currentContext?.iconFilePath, "/tmp/Desktop")
        XCTAssertEqual(currentContext?.folderStructureMode, .includeSubfolders)
    }

    /// CBW-002-show_request_context: Current File Context Does Not Expose Folder Structure Mode
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testCurrentFileContextDoesNotExposeFolderStructureMode() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Selected file",
                references: [],
                items: [
                    makeContextItem(
                        title: "Notes.pdf",
                        metadata: ["path": "/Users/test/Notes.pdf", "folderStructureMode": "includeSubfolders"],
                    ),
                ],
                attachments: [],
            ),
            addedAttachments: [],
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertNil(currentContext?.folderStructureMode)
        XCTAssertEqual(currentContext?.supportsFolderStructureMode, false)
    }

    /// CBW-002-show_request_context: Current File Context Tooltip Mentions Provider Inclusion
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testCurrentFileContextTooltipMentionsProviderInclusion() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Selected file",
                references: [],
                items: [
                    makeContextItem(
                        title: "Notes.pdf",
                        metadata: ["path": "/Users/test/Notes.pdf"],
                    ),
                ],
                attachments: [],
            ),
            addedAttachments: [],
        )

        let currentContextTooltip = aiChatRequestContextTooltipText(
            sourceLabel: "Current context",
            destinationLabel: "OpenAI",
            statusLabel: aiChatCurrentContextStatusLabel(for: state.currentContext, destinationProvider: .openai),
            statusDetail: aiChatCurrentContextStatusDetail(for: state.currentContext, destinationProvider: .openai),
        )

        XCTAssertTrue(currentContextTooltip.contains("Source: Current context"))
        XCTAssertTrue(currentContextTooltip.contains("Status: Included"))
        XCTAssertTrue(currentContextTooltip.contains("provider-native file when supported"))
    }

    /// CBW-002-show_request_context: Selected Collection Current Context Removes Voycoll Extension
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testSelectedCollectionCurrentContextRemovesVoycollExtension() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Selected collection",
                references: [makeContextReference(title: "Desktop")],
                items: [
                    makeContextItem(
                        title: "Workspace.voycoll",
                        metadata: ["path": "/tmp/Workspace.voycoll"],
                    ),
                ],
                attachments: [],
            ),
            addedAttachments: [],
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "Workspace")
        XCTAssertEqual(currentContext?.iconAssetName, "voycollFileIcon")
    }

    /// CBW-002-show_request_context: Current Collection Route Removes Voycoll Extension
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testCurrentCollectionRouteRemovesVoycollExtension() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Workspace.voycoll",
                references: [
                    makeContextReference(
                        title: "Workspace.voycoll",
                        metadata: ["route": "collection", "path": "/tmp/Workspace.voycoll"],
                    ),
                ],
                items: [],
                attachments: [],
            ),
            addedAttachments: [],
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "Workspace")
        XCTAssertEqual(currentContext?.iconAssetName, "voycollFileIcon")
    }

    /// CBW-002-show_request_context: Context Part Resolution Maps To Closed Chip States
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testContextPartResolutionMapsToClosedChipStates() {
        let fixtures = makeContextPartResolutionFixtures()

        for fixture in fixtures {
            XCTAssertEqual(aiChatContextPartStatusLabel(for: fixture.resolution), fixture.expectedLabel)
            XCTAssertEqual(aiChatContextPartStatusDetail(for: fixture.resolution), fixture.expectedDetail)
        }
    }

    // MARK: - CBW-002-show_request_context

    /// CBW-002-show_request_context: Locked Folder Reference Uses Finder Icon Path During Processing
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testLockedFolderReferenceUsesFinderIconPathDuringProcessing() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedRequestContext = makeLockedFolderReferenceContext()
        let lock = makeFolderIconRequestLock(
            context: lockedRequestContext,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
        )
        let state = AiChatFeature.State(
            sessionID: lock.context.sessionID,
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .processing(lock),
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state)
            .requestContextDisplayModel.currentResponse?.currentContext

        XCTAssertEqual(currentContext?.title, "Desktop")
        XCTAssertEqual(currentContext?.iconSystemName, "folder")
        XCTAssertEqual(currentContext?.iconFilePath, "/tmp/Desktop")
        XCTAssertEqual(currentContext?.folderStructureMode, .includeSubfolders)
    }

    // MARK: - CBW-002-add_attachment_by_drop

    /// CBW-002-add_attachment_by_drop: File URLPasteboard Resolves Attachment URLs
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testFileURLPasteboardResolvesAttachmentURLs() {
        let firstURL = URL(fileURLWithPath: "/tmp/Notes.txt")
        let duplicateURL = URL(fileURLWithPath: "/tmp/Folder/../Notes.txt")
        let folderURL = URL(filePath: "/tmp/Projects", directoryHint: .isDirectory)
        let pasteboard = NSPasteboard(name: .init("AiChatInputTextViewDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([firstURL as NSURL, duplicateURL as NSURL, folderURL as NSURL])

        let urls = AiChatInputTextView.Coordinator.fileURLs(from: pasteboard)

        XCTAssertEqual(urls, [firstURL.standardizedFileURL, folderURL.standardizedFileURL])
    }

    /// CBW-002-add_attachment_by_drop: File URLString Pasteboard Resolves Attachment URL
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testFileURLStringPasteboardResolvesAttachmentURL() {
        let collectionURL = URL(fileURLWithPath: "/tmp/Workspace.voycoll")
        let pasteboard = NSPasteboard(name: .init("AiChatInputTextViewDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(collectionURL.absoluteString, forType: .fileURL)

        let urls = AiChatInputTextView.Coordinator.fileURLs(from: pasteboard)

        XCTAssertEqual(urls, [collectionURL.standardizedFileURL])
    }

    /// CBW-002-add_attachment_by_drop: Attachment Dropping Text View Consumes File URLDrops
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testAttachmentDroppingTextViewConsumesFileURLDrops() {
        let fileURL = URL(fileURLWithPath: "/tmp/Dropped.txt")
        let pasteboard = NSPasteboard(name: .init("AiChatInputTextViewDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        let textView = AiChatInputTextView.AttachmentDroppingTextView()
        var droppedURLs: [URL] = []
        textView.onAttachmentsDropped = { droppedURLs = $0 }

        let consumed = textView.consumeFileURLs(from: pasteboard)

        XCTAssertTrue(consumed)
        XCTAssertEqual(droppedURLs, [fileURL.standardizedFileURL])
        XCTAssertEqual(textView.string, "")
    }

    // MARK: - CBW-002-show_request_context

    /// CBW-002-show_request_context: Request Context Display Model Uses Locked Snapshot During Processing And Terminal
    /// States
    /// 요청 context 표시와 첨부 동작이 CBW-002 사용자 흐름에 맞게 유지되는지 검증합니다.
    /// - 검증 내용: request context display, attachment 처리, locked snapshot 표시 결과를 확인합니다.
    /// - 사전 조건: current context, added attachment, processing snapshot fixture를 구성합니다.
    /// - 기대 결과: 사용자가 보는 context chip과 attachment 상태가 CBW-002 기대 동작과 일치합니다.
    func testRequestContextDisplayModelUsesLockedSnapshotDuringProcessingAndTerminalStates() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedRequestContext = makeLockedRequestContextForDisplayTest()
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: AiChatRequestContextSnapshot(
                    sessionID: AiChatSessionID(rawValue: UUID()),
                    requestID: AiChatRequestID(rawValue: UUID()),
                    runID: AiChatRunID(rawValue: UUID()),
                    provider: selectedHandle.provider,
                    model: selectedHandle,
                    selectedModel: nil,
                    selectedModelRow: catalogRows[0],
                    selectedThinking: nil,
                    sessionStatus: .active,
                    currentContext: makeContextSnapshot(summary: "Live context"),
                    requestContext: lockedRequestContext,
                    promptSummary: "Hello",
                    submittedAtMs: nil,
                ),
                messages: [],
            ),
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        let processingState = makeProcessingDisplayModelState(
            catalogRows: catalogRows,
            selectedHandle: selectedHandle,
            lock: lock,
        )

        let processingDisplayModel = AiChatStateDisplayModelBuilder(state: processingState).requestContextDisplayModel
        assertProcessingLockedDisplayModel(processingDisplayModel)

        let completedState = makeCompletedDisplayModelState(
            processingState: processingState,
            catalogRows: catalogRows,
            selectedHandle: selectedHandle,
            lock: lock,
        )

        let completedDisplayModel = AiChatStateDisplayModelBuilder(state: completedState).requestContextDisplayModel
        XCTAssertEqual(completedDisplayModel.source, AiChatRequestContextDisplaySource.draft)
        XCTAssertNil(completedDisplayModel.currentResponse)
        XCTAssertEqual(completedDisplayModel.currentContext?.title, "LiveOnly.txt")
        XCTAssertEqual(completedDisplayModel.addedAttachments.map(\.title), ["LiveOnly.txt"])
    }

    // MARK: - CBW-002-change_context_folder_structure_mode

    /// CBW-002-change_context_folder_structure_mode: native menu folder projection은 두 mode를 고정 순서로 제공한다.
    /// menu item이 display title이 아닌 mode enum을 identity로 사용하고 current-context/attachment target을 포함하지 않는지 검증합니다.
    /// - 검증 내용: fixed option order, mode identity, single selection, accessibility value, target identity exclusion
    /// - 사전 조건: includeSubfolders가 선택된 folder structure menu projection입니다.
    /// - 기대 결과: 두 항목만 고정 순서로 생성되고 selected는 하나이며 item 저장 필드에 target identity가 없습니다.
    func testNativeMenuFolderProjectionProvidesTwoTargetAgnosticOptions() {
        let items = AiChatFolderStructureMenuItemDisplayModel.items(selectedMode: .includeSubfolders)

        XCTAssertEqual(items.map(\.mode), [.currentFolderOnly, .includeSubfolders])
        XCTAssertEqual(items.map(\.title), ["Current folder only", "Include subfolders"])
        XCTAssertEqual(items.filter(\.isSelected).map(\.mode), [.includeSubfolders])
        XCTAssertEqual(items.map(\.accessibilityLabel), ["Current folder only", "Include subfolders"])
        XCTAssertEqual(items.map(\.accessibilityValue), ["Not selected", "Selected"])
        XCTAssertTrue(items.allSatisfy(\.isEnabled))

        let storedFieldNames = Set(items.flatMap { item in
            Mirror(reflecting: item).children.compactMap(\.label)
        })
        XCTAssertEqual(storedFieldNames, Set([
            "mode",
            "title",
            "isSelected",
            "isEnabled",
            "accessibilityLabel",
            "accessibilityValue",
        ]))
    }
}

extension CBW002RequestContextManagementTests {
    /// CBW-002-change_context_folder_structure_mode: current context mode 변경은 attachment mode를 변경하지 않는다.
    /// current context aggregate target이 added attachment의 독립 metadata까지 확장되지 않는지 검증합니다.
    /// - 검증 내용: current context folder mode 변경 후 두 attachment의 metadata 불변을 확인합니다.
    /// - 사전 조건: current folder context와 서로 다른 mode를 가진 folder attachment 두 개가 있습니다.
    /// - 기대 결과: current context만 includeSubfolders가 되고 attachment mode는 기존 값을 유지합니다.
    func testFolderStructureModeCurrentContextPreservesAttachmentModes() async {
        let folderPath = URL(filePath: "/tmp/Projects", directoryHint: .isDirectory).standardizedFileURL
            .path(percentEncoded: false)
        let folderKey = makeCBW002FolderKey(.reference, folderPath)
        let firstAttachment = makeCBW002FolderDraftAttachment(
            id: "first-folder",
            title: "First",
            path: "/tmp/First",
            mode: .currentFolderOnly,
        )
        let secondAttachment = makeCBW002FolderDraftAttachment(
            id: "second-folder",
            title: "Second",
            path: "/tmp/Second",
            mode: .includeSubfolders,
        )
        let attachments = [firstAttachment, secondAttachment]
        let store = TestStore(initialState: AiChatFeature.State(
            currentContext: makeCBW002FolderContext(summary: "Projects", folderPath: folderPath),
            addedAttachments: attachments,
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

        XCTAssertEqual(store.state.addedAttachments, attachments)
    }

    /// CBW-002-change_context_folder_structure_mode: attachment mode 변경은 exact attachment ID만 갱신한다.
    /// attachment target action이 current context 또는 다른 attachment로 번지지 않는지 검증합니다.
    /// - 검증 내용: matching ID metadata 변경과 current context/other attachment 불변을 확인합니다.
    /// - 사전 조건: current folder context와 folder attachment 두 개가 모두 currentFolderOnly입니다.
    /// - 기대 결과: 선택한 attachment만 includeSubfolders로 변경됩니다.
    func testFolderStructureModeAttachmentTargetsExactID() async {
        let currentContext = makeCBW002FolderContext(
            summary: "Projects",
            folderPath: "/tmp/Projects",
            mode: .currentFolderOnly,
        )
        let target = makeCBW002FolderDraftAttachment(
            id: "target-folder",
            title: "Target",
            path: "/tmp/Target",
            mode: .currentFolderOnly,
        )
        let other = makeCBW002FolderDraftAttachment(
            id: "other-folder",
            title: "Other",
            path: "/tmp/Other",
            mode: .currentFolderOnly,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            currentContext: currentContext,
            addedAttachments: [target, other],
        )) {
            AiChatFeature()
        }

        await store.send(.folderStructureModeChanged(.attachment(target.id), .includeSubfolders)) { state in
            state.addedAttachments[0] = makeCBW002FolderDraftAttachment(
                id: "target-folder",
                title: "Target",
                path: "/tmp/Target",
                mode: .includeSubfolders,
            )
        }

        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertEqual(store.state.addedAttachments[1], other)
    }

    /// CBW-002-change_context_folder_structure_mode: 제거된 attachment의 stale mode action은 no-op이다.
    /// menu 생성 뒤 chip이 제거된 race에서 이전 ID가 다른 target으로 fallback되지 않는지 검증합니다.
    /// - 검증 내용: stale attachment ID action 이후 current context와 remaining attachment 불변을 확인합니다.
    /// - 사전 조건: current folder context와 removed/remaining folder attachment가 있고 removed를 먼저 삭제합니다.
    /// - 기대 결과: stale mode action은 crash 없이 상태를 변경하지 않습니다.
    func testFolderStructureModeRemovedAttachmentActionIsNoOp() async {
        let currentContext = makeCBW002FolderContext(
            summary: "Projects",
            folderPath: "/tmp/Projects",
            mode: .currentFolderOnly,
        )
        let removed = makeCBW002FolderDraftAttachment(
            id: "removed-folder",
            title: "Removed",
            path: "/tmp/Removed",
            mode: .currentFolderOnly,
        )
        let remaining = makeCBW002FolderDraftAttachment(
            id: "remaining-folder",
            title: "Remaining",
            path: "/tmp/Remaining",
            mode: .currentFolderOnly,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            currentContext: currentContext,
            addedAttachments: [removed, remaining],
        )) {
            AiChatFeature()
        }

        await store.send(.removeAddedAttachment(removed.id)) { state in
            state.addedAttachments = [remaining]
        }
        await store.send(.folderStructureModeChanged(.attachment(removed.id), .includeSubfolders))

        XCTAssertEqual(store.state.currentContext, currentContext)
        XCTAssertEqual(store.state.addedAttachments, [remaining])
    }

    /// CBW-002-change_context_folder_structure_mode: 동일·중첩 path attachment도 ID별 mode를 유지한다.
    /// path 관계가 attachment target identity를 합치거나 nested de-dup으로 오인되지 않는지 검증합니다.
    /// - 검증 내용: 동일 path 두 target과 child path target의 metadata를 ID별로 확인합니다.
    /// - 사전 조건: distinct ID의 same-path attachment 둘과 nested-path attachment 하나가 있습니다.
    /// - 기대 결과: 각 action의 exact ID만 변경되고 동일·중첩 path의 다른 target은 유지됩니다.
    func testFolderStructureModeSameAndNestedPathsRemainIndependent() async {
        let sharedPath = "/tmp/Projects"
        let firstSamePath = makeCBW002FolderDraftAttachment(
            id: "same-path-first",
            title: "Projects A",
            path: sharedPath,
            mode: .currentFolderOnly,
        )
        let secondSamePath = makeCBW002FolderDraftAttachment(
            id: "same-path-second",
            title: "Projects B",
            path: sharedPath,
            mode: .currentFolderOnly,
        )
        let nestedPath = makeCBW002FolderDraftAttachment(
            id: "nested-path",
            title: "Feature",
            path: "\(sharedPath)/Feature",
            mode: .currentFolderOnly,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            addedAttachments: [firstSamePath, secondSamePath, nestedPath],
        )) {
            AiChatFeature()
        }

        await store.send(.folderStructureModeChanged(.attachment(firstSamePath.id), .includeSubfolders)) { state in
            state.addedAttachments[0] = makeCBW002FolderDraftAttachment(
                id: "same-path-first",
                title: "Projects A",
                path: sharedPath,
                mode: .includeSubfolders,
            )
        }
        await store.send(.folderStructureModeChanged(.attachment(nestedPath.id), .includeSubfolders)) { state in
            state.addedAttachments[2] = makeCBW002FolderDraftAttachment(
                id: "nested-path",
                title: "Feature",
                path: "\(sharedPath)/Feature",
                mode: .includeSubfolders,
            )
        }

        XCTAssertEqual(
            store.state.addedAttachments.map { $0.metadata["folderStructureMode"] },
            [
                AiChatFolderStructureMode.includeSubfolders.rawValue,
                AiChatFolderStructureMode.currentFolderOnly.rawValue,
                AiChatFolderStructureMode.includeSubfolders.rawValue,
            ],
        )
    }
}

extension CBW002RequestContextManagementTests {
    // MARK: - CBW-002-show_request_context

    /// CBW-002-show_request_context: file icon 완료는 current path와 generation이 일치하고 취소되지 않을 때만 반영한다.
    /// chip이 빠르게 재사용될 때 이전 detached 결과가 현재 icon state를 덮어쓰지 않는 경계를 검증합니다.
    /// - 검증 내용: same path/generation 성공과 path mismatch, generation mismatch, cancellation 거부를 확인합니다.
    /// - 사전 조건: captured file path와 current path/generation 조합을 직접 구성합니다.
    /// - 기대 결과: 현재 uncancelled request만 true이고 stale 또는 cancelled request는 모두 false입니다.
    func testShowRequestContextRejectsCancelledOrStaleFileIconResolution() {
        XCTAssertTrue(AiChatRequestContextIconResolution.shouldApply(
            capturedPath: "/tmp/Current.txt",
            currentPath: "/tmp/Current.txt",
            capturedGeneration: 3,
            currentGeneration: 3,
            isCancelled: false,
        ))
        XCTAssertFalse(AiChatRequestContextIconResolution.shouldApply(
            capturedPath: "/tmp/Old.txt",
            currentPath: "/tmp/Current.txt",
            capturedGeneration: 3,
            currentGeneration: 3,
            isCancelled: false,
        ))
        XCTAssertFalse(AiChatRequestContextIconResolution.shouldApply(
            capturedPath: "/tmp/Current.txt",
            currentPath: "/tmp/Current.txt",
            capturedGeneration: 2,
            currentGeneration: 3,
            isCancelled: false,
        ))
        XCTAssertFalse(AiChatRequestContextIconResolution.shouldApply(
            capturedPath: "/tmp/Current.txt",
            currentPath: "/tmp/Current.txt",
            capturedGeneration: 3,
            currentGeneration: 3,
            isCancelled: true,
        ))
    }

    /// CBW-002-show_request_context: file icon은 WorkspaceClient 비동기 task와 고정 placeholder를 사용한다.
    /// chip body가 AppKit singleton을 동기 호출하지 않고 asset/system icon 경로는 즉시 렌더링하는지 검증합니다.
    /// - 검증 내용: dependency, @State, task(id:), explicit cancellation, path guard, 11x11 placeholder source 계약을 확인합니다.
    /// - 사전 조건: production AiChatInputBar source의 request-context chip subtree를 읽습니다.
    /// - 기대 결과: NSWorkspace 직접 호출은 없고 file만 async이며 asset/system branch는 synchronous 상태로 남습니다.
    func testShowRequestContextLoadsFileIconAsynchronouslyWithStablePlaceholder() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/VoyagerFeaturesAiChat/Ui/AiChatInputBar.swift"),
            encoding: .utf8,
        )
        let chipStart = try XCTUnwrap(source.range(of: "private struct AiChatRemovableRequestContextChip: View"))
        let resolutionStart = try XCTUnwrap(source.range(of: "enum AiChatRequestContextIconResolution"))
        let chip = String(source[chipStart.lowerBound ..< resolutionStart.lowerBound])

        XCTAssertTrue(chip.contains("@Dependency(\\.workspaceClient)\n    private var workspaceClient"))
        XCTAssertTrue(chip.contains("@State private var resolvedFileIcon: NSImage?"))
        XCTAssertTrue(chip.contains(".task(id: iconFilePath)"))
        XCTAssertTrue(chip.contains("let icon = await workspaceClient.iconForFileAsync(path)"))
        XCTAssertTrue(chip.contains("iconLoadTask?.cancel()"))
        XCTAssertTrue(chip.contains("currentPath: currentIconFilePath"))
        XCTAssertTrue(chip.contains("resolvedFileIcon = nil"))
        XCTAssertTrue(chip.contains("Color.clear"))
        XCTAssertTrue(chip.contains(".frame(width: 11, height: 11)"))
        XCTAssertTrue(chip.contains("} else if let iconAssetName {"))
        XCTAssertTrue(chip.contains("} else if let iconSystemName {"))
        XCTAssertFalse(chip.contains("NSWorkspace.shared.icon(forFile:"))
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
        let sessionID = AiChatSessionID(rawValue: UUID())
        let lockedContext = AiChatLockedRequestContextSnapshot(
            currentContext: makeCBW002CurrentContext(title: "Locked.md", path: "/tmp/Locked.md"),
            addedAttachments: [makeCBW002LockedAttachment(id: "locked", title: "LockedNotes.txt")],
        )
        let requestContext = makeRequestContext(
            sessionID: sessionID,
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
            sessionID: sessionID,
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

    func makeCBW002AttachmentSessionID() -> AiChatSessionID {
        AiChatSessionID(rawValue: UUID(uuid: (
            0x22, 0x22, 0x22, 0x22,
            0x22, 0x22,
            0x33, 0x33,
            0x44, 0x44,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x02,
        )))
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

private func makeCBW002FolderDraftAttachment(
    id: String,
    title: String,
    path: String,
    mode: AiChatFolderStructureMode,
) -> AiChatAttachmentDraft {
    let folderURL = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
    return AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: id),
        source: .folder,
        displayTitle: title,
        sourceLocation: AiChatAttachmentSourceLocation(
            fileURL: folderURL,
            filePath: folderURL.path(percentEncoded: false),
        ),
        metadata: ["folderStructureMode": mode.rawValue],
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

// Request context display model fixture helpers

private struct ContextPartResolutionFixture {
    let resolution: AiChatContextPartResolution
    let expectedLabel: String
    let expectedDetail: String
}

private func makeContextPartResolutionFixtures() -> [ContextPartResolutionFixture] {
    makeContextPartSuccessResolutionFixtures() + makeContextPartFailureResolutionFixtures()
}

private func makeContextPartSuccessResolutionFixtures() -> [ContextPartResolutionFixture] {
    [
        ContextPartResolutionFixture(
            resolution: .inlineText(text: "Hello", metadata: [:]),
            expectedLabel: "Included",
            expectedDetail: "Included as text",
        ),
        ContextPartResolutionFixture(
            resolution: .partialText(text: "Hello", truncated: true, metadata: [:]),
            expectedLabel: "Partial",
            expectedDetail: "Included first 64 KiB as text",
        ),
        ContextPartResolutionFixture(
            resolution: .partialText(text: "Hello", truncated: false, metadata: [:]),
            expectedLabel: "Included",
            expectedDetail: "Included as text",
        ),
        ContextPartResolutionFixture(
            resolution: .referenceOnly(metadata: [:]),
            expectedLabel: "Reference only",
            expectedDetail: "Reference only; contents not included",
        ),
        ContextPartResolutionFixture(
            resolution: .referenceOnly(metadata: ["collectionItemPaths": "/tmp/A\n/tmp/B"]),
            expectedLabel: "Collection paths",
            expectedDetail: "Collection paths only; contents not included",
        ),
    ]
}

private func makeContextPartFailureResolutionFixtures() -> [ContextPartResolutionFixture] {
    [
        ContextPartResolutionFixture(
            resolution: .collectionPathList(paths: ["/tmp/A", "/tmp/B"], metadata: [:]),
            expectedLabel: "Collection paths",
            expectedDetail: "Collection paths only; contents not included",
        ),
        ContextPartResolutionFixture(
            resolution: .providerNativeFile(kind: .plainTextDocument, mimeType: "text/plain", metadata: [:]),
            expectedLabel: "Uploaded/native",
            expectedDetail: "Uploaded natively as text/plain",
        ),
        ContextPartResolutionFixture(
            resolution: .providerNativeFile(kind: .codexPathScope, mimeType: "text/plain", metadata: [:]),
            expectedLabel: "Codex path",
            expectedDetail: "Codex path reference; not uploaded",
        ),
        ContextPartResolutionFixture(
            resolution: .failure(reason: .unsupportedType, metadata: [:]),
            expectedLabel: "Unsupported",
            expectedDetail: "Not sent: unsupported type",
        ),
        ContextPartResolutionFixture(
            resolution: .failure(reason: .permissionDenied, metadata: [:]),
            expectedLabel: "Failed",
            expectedDetail: "Not sent: permissionDenied",
        ),
    ]
}

private func makeDraftAttachment(
    id: String,
    status: AiChatAttachmentDraftStatus,
    source: AiChatAttachmentSource = .file,
    displayTitle: String? = nil,
    filePath: String? = nil,
    metadata: [String: String] = [:],
) -> AiChatAttachmentDraft {
    AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: id),
        source: source,
        displayTitle: displayTitle,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: filePath),
        metadata: metadata,
        currentStatus: status,
    )
}

private func makeLockedAttachment(
    id: String,
    result: AiChatAttachmentResolutionResult,
    source: AiChatAttachmentSource = .file,
    displayTitle: String? = nil,
    filePath: String? = nil,
    metadata: [String: String] = [:],
) -> AiChatAttachmentSnapshot {
    AiChatAttachmentSnapshot(
        id: AiChatAttachmentID(rawValue: id),
        source: source,
        displayTitle: displayTitle,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: filePath),
        metadata: metadata,
        resolutionResult: result,
    )
}

private func makeContextReference(
    title: String,
    kind: AiChatContextItemKind = .reference,
    metadata: [String: String] = [:],
) -> AiChatContextReference {
    AiChatContextReference(kind: kind, identifier: title, title: title, subtitle: nil, metadata: metadata)
}

private func makeContextItem(
    title: String,
    kind: AiChatContextItemKind = .file,
    metadata: [String: String] = [:],
) -> AiChatContextItem {
    AiChatContextItem(kind: kind, identifier: title, title: title, subtitle: nil, metadata: metadata)
}

private func makeLiveStateForGroupSeparation() -> AiChatFeature.State {
    AiChatFeature.State(
        currentContext: makeContextSnapshot(
            summary: "Inspector selection",
            references: [
                makeContextReference(
                    title: "Documents",
                    kind: .folder,
                    metadata: ["path": "/tmp", "folderStructureMode": "includeSubfolders"],
                ),
            ],
            items: [makeContextItem(title: "ProjectPlan.md")],
        ),
        addedAttachments: [
            makeDraftAttachment(
                id: "notes",
                status: .resolved(.resolvedText(text: "Hello", metadata: [:])),
                displayTitle: "Notes.txt",
                metadata: ["folderStructureMode": "includeSubfolders"],
            ),
            makeDraftAttachment(
                id: "folder",
                status: .resolved(.resolvedReference(metadata: [
                    "collectionItemPaths": "/tmp/One\n/tmp/Two",
                    "folderStructureMode": "includeSubfolders",
                ])),
                source: .collectionDocument,
                displayTitle: "Workspace.voycoll",
                filePath: "/tmp/Workspace.voycoll",
                metadata: ["collectionItemPaths": "/tmp/One\n/tmp/Two", "folderStructureMode": "includeSubfolders"],
            ),
            makeDraftAttachment(
                id: "pending",
                status: .pending,
                filePath: "/tmp/Pending.txt",
            ),
            makeDraftAttachment(
                id: "partial",
                status: .resolved(.resolvedPartial(text: "Trimmed", truncated: true, metadata: [:])),
                filePath: "/tmp/Long.txt",
            ),
            makeDraftAttachment(
                id: "failed",
                status: .resolved(.failure(reason: .brokenReference, metadata: [:])),
                filePath: "/tmp/Broken.txt",
            ),
        ],
    )
}

private func assertDraftDisplayModelGroupSeparation(_ displayModel: AiChatRequestContextDisplayModel) {
    XCTAssertEqual(displayModel.source, AiChatRequestContextDisplaySource.draft)
    XCTAssertEqual(displayModel.currentContext?.title, "ProjectPlan.md")
    XCTAssertEqual(displayModel.addedAttachments.map(\.title), [
        "Notes.txt", "Workspace", "Pending.txt", "Long.txt", "Broken.txt",
    ])
    XCTAssertEqual(displayModel.addedAttachments.map(\.statusLabel), [
        "Included", "Collection paths", "", "Partial", "Failed",
    ])
    XCTAssertEqual(displayModel.addedAttachments.map(\.statusDetail), [
        "Included as text",
        "Collection paths only; contents not included",
        "",
        "Included first 64 KiB as text",
        "Not sent: brokenReference",
    ])
    XCTAssertEqual(displayModel.addedAttachments[1].iconFilePath, "/tmp/Workspace.voycoll")
    XCTAssertEqual(displayModel.addedAttachments[1].iconAssetName, "voycollFileIcon")
    XCTAssertTrue(displayModel.addedAttachments.allSatisfy(\.isRemovable))
    XCTAssertEqual(displayModel.currentContext?.folderStructureMode, .includeSubfolders)
    XCTAssertEqual(displayModel.currentContext?.supportsFolderStructureMode, true)
    XCTAssertEqual(displayModel.addedAttachments[1].folderStructureMode, .includeSubfolders)
}

private func makeLockedFolderProcessingState(
    catalogRows: [AiModelCatalogRow],
) -> (state: AiChatFeature.State, currentContext: AiChatCurrentContextChipDisplayModel?) {
    let selectedHandle = catalogRows[0].handle
    let lockedRequestContext = makeDesktopLockedRequestContext()
    let lock = makeRequestLock(
        kind: .submit,
        request: AiChatRequest(
            context: AiChatRequestContextSnapshot(
                sessionID: AiChatSessionID(rawValue: UUID()),
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                provider: selectedHandle.provider,
                model: selectedHandle,
                selectedModelRow: catalogRows[0],
                sessionStatus: .active,
                currentContext: makeContextSnapshot(summary: "Live context"),
                requestContext: lockedRequestContext,
                promptSummary: "Hello",
            ),
            messages: [],
        ),
        selectedHandle: selectedHandle,
        selectedRow: catalogRows[0],
        assistantReplacementIndex: nil,
    )
    let state = AiChatFeature.State(
        sessionID: lock.context.sessionID,
        sessionStatus: .active,
        catalogRows: catalogRows,
        selectedModelHandle: selectedHandle,
        executionPhase: .processing(lock),
    )
    let currentContext = AiChatStateDisplayModelBuilder(state: state)
        .requestContextDisplayModel.currentResponse?.currentContext
    return (state, currentContext)
}

private func makeDesktopLockedRequestContext() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: makeContextSnapshot(
            summary: "Desktop",
            references: [],
            items: [
                makeContextItem(
                    title: "Desktop",
                    kind: .folder,
                    metadata: ["path": "Desktop"],
                ),
            ],
            attachments: [],
        ),
        addedAttachments: [],
        parts: [
            AiChatLockedContextPartSnapshot(
                source: .currentContext,
                resolution: .referenceOnly(metadata: ["folderStructureMode": "includeSubfolders"]),
                canonicalPath: "/tmp/Desktop",
                displayPath: "Desktop",
                fileKind: .folder,
                displayTitle: "Desktop",
            ),
        ],
    )
}

// Attachment icon display fixture helpers

private func makeLockedSelectedImageFileRequestContext() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: AiChatCurrentContextSnapshot(
            summary: "Desktop · 1 selected",
            references: [makeImageAttachmentRouteReference()],
            items: [
                AiChatContextItem(
                    kind: .file,
                    identifier: "/Users/test/Desktop/SCR-20260528-suth.png",
                    title: "SCR-20260528-suth.png",
                    subtitle: "/Users/test/Desktop/SCR-20260528-suth.png",
                    metadata: [
                        "kind": "file",
                        "path": "/Users/test/Desktop/SCR-20260528-suth.png",
                        "selected": "true",
                    ],
                    references: [makeImageAttachmentRouteReference()],
                ),
            ],
            attachments: [],
        ),
        addedAttachments: [],
        parts: [
            makeLockedFolderReferencePart(),
            makeLockedSelectedImageFilePart(),
        ],
    )
}

private func makeLockedFolderReferencePart() -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: .currentContext,
        resolution: .referenceOnly(metadata: ["route": "folder"]),
        canonicalPath: "/Users/test/Desktop",
        displayPath: "Desktop",
        fileKind: .reference,
        displayTitle: "Desktop",
    )
}

private func makeLockedSelectedImageFilePart() -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: .currentContext,
        resolution: .providerNativeFile(
            kind: .image,
            mimeType: "image/png",
            metadata: ["mimeType": "image/png"],
        ),
        canonicalPath: "/Users/test/Desktop/SCR-20260528-suth.png",
        displayPath: "SCR-20260528-suth.png",
        fileKind: .file,
        displayTitle: "SCR-20260528-suth.png",
        mimeType: "image/png",
    )
}

private func makeImageAttachmentCurrentContext() -> AiChatCurrentContextSnapshot {
    AiChatCurrentContextSnapshot(
        summary: "Screenshot.png",
        references: [makeImageAttachmentRouteReference()],
        items: [],
        attachments: [makeImageContextAttachment()],
    )
}

private func makeImageAttachmentRouteReference() -> AiChatContextReference {
    AiChatContextReference(
        kind: .reference,
        identifier: "Desktop",
        title: "Desktop",
        subtitle: nil,
        metadata: ["route": "folder", "path": "/Users/test/Desktop"],
    )
}

private func makeImageContextAttachment() -> AiChatContextAttachment {
    AiChatContextAttachment(
        identifier: "/Users/test/Desktop/Screenshot.png",
        title: "Screenshot.png",
        subtitle: "/Users/test/Desktop/Screenshot.png",
        kind: .attachment,
        metadata: ["mimeType": "image/png", "path": "/Users/test/Desktop/Screenshot.png"],
    )
}

private func makeLockedImageAttachmentRequestContext() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: makeImageAttachmentCurrentContext(),
        addedAttachments: [],
        parts: [makeLockedImageAttachmentPart()],
    )
}

private func makeLockedImageAttachmentPart() -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: .currentContext,
        resolution: .providerNativeFile(
            kind: .image,
            mimeType: "image/png",
            metadata: ["mimeType": "image/png"],
        ),
        canonicalPath: "/Users/test/Desktop/Screenshot.png",
        displayPath: "Screenshot.png",
        fileKind: .attachment,
        displayTitle: "Screenshot.png",
        mimeType: "image/png",
    )
}

private func makeImageAttachmentRequestLock(
    context: AiChatLockedRequestContextSnapshot,
    selectedHandle: AiModelHandle,
    selectedRow: AiModelCatalogRow,
) -> AiChatRequestLock {
    makeRequestLock(
        kind: .submit,
        request: makeImageAttachmentRequest(
            context: context,
            selectedHandle: selectedHandle,
            selectedRow: selectedRow,
        ),
        selectedHandle: selectedHandle,
        selectedRow: selectedRow,
        assistantReplacementIndex: nil,
    )
}

private func makeImageAttachmentRequest(
    context: AiChatLockedRequestContextSnapshot,
    selectedHandle: AiModelHandle,
    selectedRow: AiModelCatalogRow,
) -> AiChatRequest {
    AiChatRequest(
        context: AiChatRequestContextSnapshot(
            sessionID: AiChatSessionID(rawValue: UUID()),
            requestID: AiChatRequestID(rawValue: UUID()),
            runID: AiChatRunID(rawValue: UUID()),
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: selectedRow,
            sessionStatus: .active,
            currentContext: AiChatCurrentContextSnapshot(summary: "Live context"),
            requestContext: context,
            promptSummary: "Hello",
        ),
        messages: [],
    )
}

// Folder icon display fixture helpers

private func makeLockedFolderReferenceContext() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: makeFolderIconContextSnapshot(),
        addedAttachments: [],
        parts: [makeFolderIconLockedFolderReferencePart()],
    )
}

private func makeFolderIconContextSnapshot() -> AiChatCurrentContextSnapshot {
    AiChatCurrentContextSnapshot(
        summary: "Desktop",
        references: [
            AiChatContextReference(
                kind: .reference,
                identifier: "Desktop",
                title: "Desktop",
                subtitle: nil,
                metadata: ["route": "folder", "path": "Desktop"],
            ),
        ],
        items: [],
        attachments: [],
    )
}

private func makeFolderIconLockedFolderReferencePart() -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: .currentContext,
        resolution: .referenceOnly(metadata: [
            "route": "folder",
            "folderStructureMode": "includeSubfolders",
        ]),
        canonicalPath: "/tmp/Desktop",
        displayPath: "Desktop",
        fileKind: .reference,
        displayTitle: "Desktop",
    )
}

private func makeFolderIconRequestLock(
    context: AiChatLockedRequestContextSnapshot,
    selectedHandle: AiModelHandle,
    selectedRow: AiModelCatalogRow,
) -> AiChatRequestLock {
    makeRequestLock(
        kind: .submit,
        request: makeFolderIconRequest(
            context: context,
            selectedHandle: selectedHandle,
            selectedRow: selectedRow,
        ),
        selectedHandle: selectedHandle,
        selectedRow: selectedRow,
        assistantReplacementIndex: nil,
    )
}

private func makeFolderIconRequest(
    context: AiChatLockedRequestContextSnapshot,
    selectedHandle: AiModelHandle,
    selectedRow: AiModelCatalogRow,
) -> AiChatRequest {
    AiChatRequest(
        context: AiChatRequestContextSnapshot(
            sessionID: AiChatSessionID(rawValue: UUID()),
            requestID: AiChatRequestID(rawValue: UUID()),
            runID: AiChatRunID(rawValue: UUID()),
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: selectedRow,
            sessionStatus: .active,
            currentContext: AiChatCurrentContextSnapshot(summary: "Live context"),
            requestContext: context,
            promptSummary: "Hello",
        ),
        messages: [],
    )
}

// Locked request context display fixture helpers

private func makeLockedRequestContextForDisplayTest() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: makeContextSnapshot(
            summary: "Locked request context",
            references: [
                makeContextReference(
                    title: "Locked request context",
                    metadata: ["folderStructureMode": "includeSubfolders"],
                ),
            ],
        ),
        addedAttachments: makeLockedDisplayTestAttachments(),
        parts: makeLockedDisplayTestParts(),
    )
}

private func makeLockedDisplayTestAttachments() -> [AiChatAttachmentSnapshot] {
    [
        makeLockedAttachment(
            id: "locked-ref",
            result: .resolvedReference(metadata: [
                "collectionItemPaths": "/tmp/One\n/tmp/Two",
                "folderStructureMode": "includeSubfolders",
            ]),
            source: .collectionDocument,
            displayTitle: "Workspace.voycoll",
            filePath: "/tmp/Workspace.voycoll",
            metadata: ["collectionItemPaths": "/tmp/One\n/tmp/Two", "folderStructureMode": "includeSubfolders"],
        ),
        makeLockedAttachment(
            id: "locked-native",
            result: .resolvedReference(metadata: [:]),
            displayTitle: "Design.pdf",
            filePath: "/tmp/Design.pdf",
        ),
        makeLockedAttachment(
            id: "locked-fail",
            result: .failure(reason: .permissionDenied, metadata: [:]),
            filePath: "/tmp/Secret.txt",
        ),
    ]
}

private func makeLockedDisplayTestParts() -> [AiChatLockedContextPartSnapshot] {
    [
        AiChatLockedContextPartSnapshot(
            source: .attachment,
            resolution: .collectionPathList(
                paths: ["/tmp/One", "/tmp/Two"],
                metadata: ["attachmentID": "locked-ref", "folderStructureMode": "includeSubfolders"],
            ),
            fileKind: .attachment,
            displayTitle: "Workspace.voycoll",
        ),
        AiChatLockedContextPartSnapshot(
            source: .attachment,
            resolution: .providerNativeFile(
                kind: .pdf,
                mimeType: "application/pdf",
                metadata: ["attachmentID": "locked-native"],
            ),
            fileKind: .file,
            displayTitle: "Design.pdf",
            mimeType: "application/pdf",
        ),
        AiChatLockedContextPartSnapshot(
            source: .attachment,
            resolution: .failure(
                reason: .permissionDenied,
                metadata: ["attachmentID": "locked-fail"],
            ),
            fileKind: .file,
            displayTitle: "Secret.txt",
        ),
    ]
}

private func makeProcessingDisplayModelState(
    catalogRows: [AiModelCatalogRow],
    selectedHandle: AiModelHandle,
    lock: AiChatRequestLock,
) -> AiChatFeature.State {
    AiChatFeature.State(
        sessionID: lock.context.sessionID,
        sessionStatus: .active,
        currentContext: makeContextSnapshot(summary: "Live context"),
        addedAttachments: [
            makeDraftAttachment(
                id: "draft-only",
                status: .resolved(.resolvedText(text: "Draft", metadata: [:])),
                displayTitle: "DraftOnly.txt",
            ),
        ],
        transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
        draftText: "Follow up",
        catalogRows: catalogRows,
        selectedModelHandle: selectedHandle,
        executionPhase: .processing(lock),
    )
}

private func assertProcessingLockedDisplayModel(_ displayModel: AiChatRequestContextDisplayModel) {
    XCTAssertEqual(displayModel.source, AiChatRequestContextDisplaySource.draft)
    XCTAssertEqual(displayModel.addedAttachments.map(\.title), ["DraftOnly.txt"])
    XCTAssertTrue(displayModel.addedAttachments.allSatisfy(\.isRemovable))
    guard let currentResponse = displayModel.currentResponse else {
        return XCTFail("Expected current response context section")
    }
    XCTAssertEqual(currentResponse.source, AiChatRequestContextDisplaySource.locked)
    XCTAssertEqual(currentResponse.currentContext?.title, "VoyagerEntitiesAi.swift")
    XCTAssertEqual(currentResponse.addedAttachments.map(\.title), ["Workspace", "Design.pdf", "Secret.txt"])
    XCTAssertEqual(
        currentResponse.addedAttachments.map(\.statusLabel),
        ["Collection paths", "Uploaded/native", "Failed"],
    )
    XCTAssertEqual(currentResponse.addedAttachments.map(\.statusDetail), [
        "Collection paths only; contents not included",
        "Uploaded natively as application/pdf",
        "Not sent: permissionDenied",
    ])
    XCTAssertEqual(currentResponse.addedAttachments[0].iconFilePath, "/tmp/Workspace.voycoll")
    XCTAssertEqual(currentResponse.addedAttachments[0].iconAssetName, "voycollFileIcon")
    XCTAssertTrue(currentResponse.addedAttachments.allSatisfy { !$0.isRemovable })
    XCTAssertNil(currentResponse.currentContext?.folderStructureMode)
    XCTAssertEqual(currentResponse.currentContext?.supportsFolderStructureMode, false)
    XCTAssertEqual(currentResponse.addedAttachments[0].folderStructureMode, .includeSubfolders)
}

private func makeCompletedDisplayModelState(
    processingState: AiChatFeature.State,
    catalogRows: [AiModelCatalogRow],
    selectedHandle: AiModelHandle,
    lock: AiChatRequestLock,
) -> AiChatFeature.State {
    AiChatFeature.State(
        sessionID: processingState.sessionID,
        sessionStatus: .active,
        currentContext: makeCompletedLiveContextSnapshot(),
        addedAttachments: makeCompletedLiveAttachments(),
        transcriptHistory: [AiChatMessage(role: .assistant, content: "Done")],
        draftText: "",
        catalogRows: catalogRows,
        selectedModelHandle: selectedHandle,
        executionPhase: .completed(lock),
    )
}

private func makeCompletedLiveContextSnapshot() -> AiChatCurrentContextSnapshot {
    makeContextSnapshot(
        summary: "Edited live context",
        references: [
            makeContextReference(
                title: "Documents",
                metadata: ["folderStructureMode": "includeSubfolders"],
            ),
        ],
        items: [makeContextItem(title: "LiveOnly.txt")],
    )
}

private func makeCompletedLiveAttachments() -> [AiChatAttachmentDraft] {
    [
        makeDraftAttachment(
            id: "live-only",
            status: .resolved(.resolvedText(text: "Live", metadata: [:])),
            displayTitle: "LiveOnly.txt",
            metadata: ["folderStructureMode": "includeSubfolders"],
        ),
    ]
}
