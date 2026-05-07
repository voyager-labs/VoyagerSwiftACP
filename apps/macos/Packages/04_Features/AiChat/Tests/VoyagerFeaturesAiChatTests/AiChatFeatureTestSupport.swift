import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

func makeUUID(_ rawValue: String, file: StaticString = #filePath, line: UInt = #line) -> UUID {
    guard let uuid = UUID(uuidString: rawValue) else {
        XCTFail("Invalid UUID literal: \(rawValue)", file: file, line: line)
        return UUID()
    }

    return uuid
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
        )
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
        )
    ],
    items: [AiChatContextItem] = [
        AiChatContextItem(
            kind: .file,
            identifier: "file-1",
            title: "VoyagerEntitiesAi.swift",
            subtitle: "Source file",
            metadata: ["path": "Sources/VoyagerEntitiesAi/VoyagerEntitiesAi.swift"],
        )
    ],
    attachments: [AiChatContextAttachment] = [
        AiChatContextAttachment(
            identifier: "attachment-1",
            title: "Screenshot",
            subtitle: "Current state",
            metadata: ["mimeType": "image/png"],
        )
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
    promptSummary: String = "Hello",
) -> AiChatRequestContextSnapshot {
    AiChatRequestContextSnapshot(
        sessionID: sessionID,
        requestID: requestID,
        runID: runID,
        provider: model.provider,
        model: model,
        selectedModelRow: selectedRow,
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
        try await loadHandler(sessionID)
    }

    func save(_ snapshot: AiChatSessionSnapshot) async {
        snapshots.append(snapshot)
    }
}
