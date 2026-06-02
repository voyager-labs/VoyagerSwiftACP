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
) -> AiChatContextItem {
    AiChatContextItem(kind: .file, identifier: path, title: title, subtitle: path, metadata: ["path": path])
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
