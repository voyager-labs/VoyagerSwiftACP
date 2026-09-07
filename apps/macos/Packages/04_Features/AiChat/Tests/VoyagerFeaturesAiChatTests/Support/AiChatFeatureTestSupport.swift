import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// AiChat feature tests에서 공유하는 fixture와 dependency double support.
// Specs와 flat contract tests가 공통 provider/model/session fixture를 직접 재사용한다.

func makeFixedDate(milliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
}

func makeUUID(_ rawValue: String, file: StaticString = #filePath, line: UInt = #line) -> UUID {
    guard let uuid = UUID(uuidString: rawValue) else {
        XCTFail("Invalid UUID literal: \(rawValue)", file: file, line: line)
        return UUID()
    }

    return uuid
}

func makeProviderModels() -> [AiProviderModel] {
    [
        AiProviderModel(
            id: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            displayName: "GPT-4.1 Mini",
            providerDisplayName: ProviderDescriptor.descriptor(for: .openai)?.displayName ?? "OpenAI",
            thinkingCapability: .unknown(reason: .init(message: "Thinking capability metadata is not loaded yet.")),
            unavailableReason: nil,
        ),
        AiProviderModel(
            id: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-20250514"),
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-20250514",
            displayName: "Claude Sonnet 4",
            providerDisplayName: ProviderDescriptor.descriptor(for: .anthropic)?.displayName ?? "Anthropic",
            thinkingCapability: .unknown(reason: .init(message: "Thinking capability metadata is not loaded yet.")),
            unavailableReason: nil,
        ),
    ]
}

func makeThinkingCapableProviderModels() -> [AiProviderModel] {
    [
        AiProviderModel(
            id: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            displayName: "GPT-4.1 Mini",
            providerDisplayName: ProviderDescriptor.descriptor(for: .openai)?.displayName ?? "OpenAI",
            thinkingCapability: .effort(values: [.low, .medium, .high], defaultValue: .medium),
            unavailableReason: nil,
        ),
        AiProviderModel(
            id: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-20250514"),
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-20250514",
            displayName: "Claude Sonnet 4",
            providerDisplayName: ProviderDescriptor.descriptor(for: .anthropic)?.displayName ?? "Anthropic",
            thinkingCapability: .effort(values: [.minimal, .low, .medium], defaultValue: .low),
            unavailableReason: nil,
        ),
    ]
}

func makeCatalogRows() -> [AiModelCatalogRow] {
    [
        AiModelCatalogRow(
            handle: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            subtitle: nil,
            sortOrder: 10,
            isDefault: true,
            isRecommended: true,
        ),
        AiModelCatalogRow(
            handle: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-20250514"),
            displayName: "Claude Sonnet 4",
            authMethod: .apiKey,
            subtitle: "Reasoning-first chat",
            sortOrder: 20,
            isDefault: false,
            isRecommended: false,
        ),
    ]
}

func makeUnresolvableModelHandle() -> AiModelHandle {
    AiModelHandle(provider: .openai, rawValue: "unresolvable-model")
}

func makeContextSnapshot(
    summary: String = "Four files selected",
    references: [AiChatContextReference] = [
        AiChatContextReference(
            kind: .reference,
            identifier: "ref-1",
            title: "Readme.md",
            subtitle: "Project readme",
            metadata: ["path": "docs/Readme.md"],
        ),
    ],
    items: [AiChatContextItem] = [
        AiChatContextItem(
            kind: .file,
            identifier: "file-1",
            title: "VoyagerEntitiesAi.swift",
            subtitle: "Source file",
            metadata: ["path": "Sources/VoyagerEntitiesAi/VoyagerEntitiesAi.swift"],
        ),
    ],
    attachments: [AiChatContextAttachment] = [
        AiChatContextAttachment(
            identifier: "attachment-1",
            title: "Screenshot",
            subtitle: "Current state",
            metadata: ["mimeType": "image/png"],
        ),
    ],
) -> AiChatCurrentContextSnapshot {
    AiChatCurrentContextSnapshot(
        summary: summary,
        references: references,
        items: items,
        attachments: attachments,
    )
}

func makeRequestContext(
    sessionID: AiChatSessionID,
    requestID: AiChatRequestID,
    runID: AiChatRunID,
    model: AiModelHandle,
    selectedRow: AiModelCatalogRow,
    selectedModel: AiProviderModel? = nil,
    selectedThinking: AiThinkingSelection? = nil,
    promptSummary: String = "Hello",
) -> AiChatRequestContextSnapshot {
    AiChatRequestContextSnapshot(
        sessionID: sessionID,
        requestID: requestID,
        runID: runID,
        provider: model.provider,
        model: model,
        selectedModel: selectedModel,
        selectedModelRow: selectedRow,
        selectedThinking: selectedThinking,
        sessionStatus: .active,
        currentContext: makeContextSnapshot(),
        promptSummary: promptSummary,
        submittedAtMs: nil,
    )
}

func makeRequestLock(
    kind: AiChatRequestKind,
    request: AiChatRequest,
    selectedHandle: AiModelHandle,
    selectedRow: AiModelCatalogRow,
    assistantReplacementIndex: Int?,
    customTitle: String? = nil,
    persistenceTranscriptHistory: [AiChatMessage]? = nil,
) -> AiChatRequestLock {
    AiChatRequestLock(
        kind: kind,
        requestID: request.context.requestID,
        runID: request.context.runID,
        context: request.context,
        request: request,
        selectedModelHandle: selectedHandle,
        selectedModelRow: selectedRow,
        assistantReplacementIndex: assistantReplacementIndex,
        persistenceTranscriptHistory: persistenceTranscriptHistory,
        customTitle: customTitle,
        historyTruncation: AiChatHistoryTruncationMetadata(
            includedMessageCount: request.messages.count,
            excludedMessageCount: 0,
            budget: 24000,
            truncationReason: nil,
        ),
        observabilitySummary: AiChatRequestObservabilitySummary(
            submittedAtMs: request.context.submittedAtMs ?? 0,
        ),
    )
}

final class AiChatExecutionStreamDriver: @unchecked Sendable {
    private(set) var requests: [AiChatRequest] = []
    private var continuations: [AsyncStream<AiChatEvent>.Continuation] = []

    func stream(for request: AiChatRequest) -> AsyncStream<AiChatEvent> {
        requests.append(request)
        return AsyncStream { continuation in
            self.continuations.append(continuation)
        }
    }

    func yield(_ event: AiChatEvent, at index: Int = 0) {
        guard continuations.indices.contains(index) else { return }
        continuations[index].yield(event)
    }

    func finish(at index: Int = 0) {
        guard continuations.indices.contains(index) else { return }
        continuations[index].finish()
    }
}

final class AiChatSessionPersistenceSpy: @unchecked Sendable {
    private(set) var snapshots: [AiChatSessionSnapshot] = []
    private let loadHandler: @Sendable (AiChatSessionID) async throws -> AiChatSessionSnapshot?

    init(loadHandler: @escaping @Sendable (AiChatSessionID) async throws -> AiChatSessionSnapshot? = { _ in nil }) {
        self.loadHandler = loadHandler
    }

    func loadSession(_ sessionID: AiChatSessionID) async throws -> AiChatSessionSnapshot? {
        if let savedSnapshot = snapshots.last(where: { $0.sessionID == sessionID }) {
            return savedSnapshot
        }
        return try await loadHandler(sessionID)
    }

    func save(_ snapshot: AiChatSessionSnapshot) async -> AiChatSessionSnapshot {
        snapshots.append(snapshot)
        return snapshot
    }
}

func makeProviderRecord(
    provider: AiProvider,
    authMethod: ProviderAuthMethod = .apiKey,
    state: ProviderConnectionState = .connected,
    credential: StoredCredentialPayload? = nil,
) -> ProviderRecordFile {
    let resolvedCredential = credential ?? .apiKey(APIKeyCredentialFile(secret: "sk-test-valid"))
    return ProviderRecordFile(
        providerId: provider,
        authMethod: authMethod,
        credential: resolvedCredential,
        snapshot: ProviderSnapshotFile(lastKnownStatus: state),
    )
}

func makeConnectionsFile(
    providers: [ProviderRecordFile],
    updatedAtMs: Int64 = 1,
    lastUsedProviderId: AiProvider? = nil,
) -> AIConnectionsFile {
    AIConnectionsFile(
        updatedAtMs: updatedAtMs,
        lastUsedProviderId: lastUsedProviderId,
        providers: Dictionary(uniqueKeysWithValues: providers.map { ($0.providerId.rawValue, $0) }),
    )
}

@MainActor
func resolvePendingRequestContext(
    _ store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
    update: @escaping (inout AiChatFeature.State) -> Void = { _ in },
) async {
    guard let pendingRequest = store.state.pendingRequestStart else { return }
    let selectedModel = pendingRequest.selectedModel
    let sourceContext = pendingRequest.preparedRequest.requestContextSource
    let input = AiChatContextPartResolverInput(
        provider: selectedModel.provider,
        rawModelID: selectedModel.rawModelID,
        requestFamily: testRequestFamily(for: selectedModel.provider),
        currentContext: sourceContext?.currentContext ?? store.state.currentContext,
        attachments: sourceContext == nil ? store.state.addedAttachments : [],
    )
    let resolvedContext = await AiChatContextPartResolverClient.live().resolve(input)
    await store.receive(.requestContextResolved(pendingRequest.resolutionID, resolvedContext)) { state in
        update(&state)
    }
}

private func testRequestFamily(for provider: AiProvider) -> AiChatContextPartResolverRequestFamily {
    switch provider {
    case .openai:
        .openAIResponses
    case .anthropic:
        .anthropicMessages
    case .chatgptCodex:
        .codexCLI
    }
}
