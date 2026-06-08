@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

func assertRegistryRoute(
    provider: AiProvider,
    credential: StoredCredentialPayload,
    rawModelID: String,
    selectedThinking: AiThinkingSelection? = AiThinkingSelection.none,
    capability thinkingCapability: AiModelThinkingCapability? = nil,
) throws {
    let request = providerExecutionMakeRequest(
        provider: provider,
        rawModelID: rawModelID,
        selectedThinking: selectedThinking,
        capability: thinkingCapability,
    )
    let configuration = URLSessionConfiguration.ephemeral
    let session = URLSession(configuration: configuration)
    let expectedNow: Int64 = 42424
    nonisolated(unsafe) var executedProviders: [AiProvider] = []
    nonisolated(unsafe) var observedInput: AiChatProviderExecutionInput?
    let codexExecutor: AiChatProviderCodexExecutor = { _, _, _, _, _ in
        "registry-stub"
    }
    let executor = AiChatProviderExecutor { input in
        executedProviders.append(provider)
        observedInput = input
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(context: input.preflight.executionContext))
            continuation.finish()
        }
    }
    let registry = AiChatProviderExecutorRegistry(executors: [provider: executor])
    let client = AiChatProviderExecutionClient.live(
        session: session,
        now: { expectedNow },
        codexExecutor: codexExecutor,
        registry: registry,
    )

    let events = try providerExecutionCollect(client.execute(request, credential))

    XCTAssertEqual(events, [.started(context: request.context)])
    XCTAssertEqual(executedProviders, [provider])
    let input = try XCTUnwrap(observedInput)
    XCTAssertEqual(input.preflight, try AiChatProviderPreflight.prepare(request, credential: credential))
    XCTAssertEqual(ObjectIdentifier(input.session), ObjectIdentifier(session))
    XCTAssertEqual(input.now(), expectedNow)

    assertCodexProbe(provider: provider, rawModelID: rawModelID, input: input)
}

func assertCodexProbe(
    provider: AiProvider,
    rawModelID: String,
    input: AiChatProviderExecutionInput,
) {
    guard provider == .chatgptCodex else { return }
    let prompt = AiChatProviderExecutionClient.makeCodexPrompt(payload: input.preflight.payload)
    XCTAssertEqual(input.preflight.payload.rawModelID, rawModelID)
    XCTAssertEqual(input.preflight.payload.thinking, .effort(.high))
    XCTAssertTrue(prompt.contains("current_context:"))
}

func makeCancellableCodexClient(
    executorEntered: XCTestExpectation,
    executorCancelled: XCTestExpectation,
) -> AiChatProviderExecutionClient {
    AiChatProviderExecutionClient.live(
        now: { 30002 },
        codexExecutor: { model, prompt, thinking, credential, _ in
            XCTAssertEqual(model, "gpt-5-codex")
            XCTAssertEqual(thinking, .effort(.high))
            XCTAssertEqual(credential.accessToken, "codex-token")
            XCTAssertTrue(prompt.contains("current_context:"))
            executorEntered.fulfill()
            return try await providerExecutionWaitForCancellation(onCancel: executorCancelled.fulfill)
        },
    )
}

func makeCancellableRegistry(
    producerEntered: XCTestExpectation,
    producerCancelled: XCTestExpectation,
) -> AiChatProviderExecutorRegistry {
    AiChatProviderExecutorRegistry(executors: [
        .openai: AiChatProviderExecutor { input in
            providerExecutionCancellableRegistryStream(
                context: input.preflight.executionContext,
                producerEntered: producerEntered,
                producerCancelled: producerCancelled,
            )
        },
    ])
}

func providerExecutionMakeLiveClient(
    now: Int64 = 5000,
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data),
) -> AiChatProviderExecutionClient {
    ProviderExecutionURLProtocol.reset()
    ProviderExecutionURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ProviderExecutionURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return .live(session: session, now: { now })
}

func providerExecutionMakeLiveClient() -> AiChatProviderExecutionClient {
    providerExecutionMakeLiveClient { _ in
        throw URLError(.unsupportedURL)
    }
}

func providerExecutionMakeRequest(
    provider: AiProvider,
    rawModelID: String = "gpt-5.5",
    modelHandle: AiModelHandle? = nil,
    selectedModel explicitSelectedModel: AiProviderModel? = nil,
    modelProvider: AiProvider? = nil,
    selectedThinking: AiThinkingSelection? = AiThinkingSelection.none,
    capability thinkingCapability: AiModelThinkingCapability? = nil,
    supportsThinkingNone: Bool = false,
) -> AiChatRequest {
    let resolvedProvider = modelProvider ?? provider
    let model = modelHandle ?? AiModelHandle(provider: resolvedProvider, rawValue: rawModelID)
    let selectedModel = explicitSelectedModel ?? thinkingCapability.map { capability in
        AiProviderModel(
            id: AiModelHandle(provider: resolvedProvider, rawValue: rawModelID),
            provider: resolvedProvider,
            rawModelID: rawModelID,
            displayName: rawModelID,
            providerDisplayName: resolvedProvider.rawValue,
            thinkingCapability: capability,
            supportsThinkingNone: supportsThinkingNone,
            unavailableReason: nil,
        )
    }
    return AiChatRequest(
        context: AiChatRequestContextSnapshot(
            requestID: AiChatRequestID(rawValue: providerExecutionMakeUUID("00000000-0000-0000-0000-000000000010")),
            runID: AiChatRunID(rawValue: providerExecutionMakeUUID("00000000-0000-0000-0000-000000000011")),
            provider: provider,
            model: model,
            selectedModel: selectedModel,
            selectedThinking: selectedThinking,
            sessionStatus: .idle,
            currentContext: .init(summary: "workspace context"),
            requestContext: providerExecutionMakeLockedRequestContextFixture(),
            promptSummary: nil,
            submittedAtMs: 1,
        ),
        messages: [AiChatMessage(role: .user, content: "Ping")],
    )
}

func providerExecutionAssertOpenAIThinkingLoweringMatrix() throws {
    let capability = AiModelThinkingCapability.effort(values: [.low, .high], defaultValue: nil)

    let omitted = try providerExecutionPrepareOpenAIThinking(selection: nil, capability: capability)
    XCTAssertNil(omitted.payload.thinking)
    XCTAssertTrue(omitted.warnings.isEmpty)

    let unsupportedNone = try providerExecutionPrepareOpenAIThinking(
        selection: AiThinkingSelection.none,
        capability: capability,
    )
    XCTAssertNil(unsupportedNone.payload.thinking)
    XCTAssertEqual(unsupportedNone.warnings.count, 1)

    let supportedNone = try providerExecutionPrepareOpenAIThinking(
        selection: AiThinkingSelection.none,
        capability: capability,
        supportsThinkingNone: true,
    )
    XCTAssertEqual(supportedNone.payload.thinking, AiChatProviderThinkingPayload.none)
    XCTAssertTrue(supportedNone.warnings.isEmpty)

    let effort = try providerExecutionPrepareOpenAIThinking(selection: .effort(.high), capability: capability)
    XCTAssertEqual(effort.payload.thinking, .effort(.high))

    let tokenBudget = try providerExecutionPrepareOpenAIThinking(selection: .tokenBudget(1024), capability: capability)
    XCTAssertNil(tokenBudget.payload.thinking)
    XCTAssertEqual(
        tokenBudget.warnings,
        [
            .omittedThinkingSelection(
                provider: .openai,
                selection: .tokenBudget(1024),
                reason: "The model capability does not advertise token-budget thinking.",
            ),
        ],
    )
}

func providerExecutionPrepareOpenAIThinking(
    selection: AiThinkingSelection?,
    capability: AiModelThinkingCapability,
    supportsThinkingNone: Bool = false,
) throws -> AiChatProviderPreflightResult {
    try AiChatProviderPreflight.prepare(
        providerExecutionMakeRequest(
            provider: .openai,
            selectedThinking: selection,
            capability: capability,
            supportsThinkingNone: supportsThinkingNone,
        ),
        credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
    )
}

func providerExecutionMakePreparedRequestFixture() -> AiChatRequest {
    let selectedModel = AiProviderModel(
        id: AiModelHandle(provider: .openai, rawValue: "selected-model-id"),
        provider: .openai,
        rawModelID: "selected-model-id",
        displayName: "Pretty Name",
        providerDisplayName: "OpenAI",
        thinkingCapability: .effort(values: [.high], defaultValue: nil),
        unavailableReason: nil,
    )

    let lockedRequestContext = providerExecutionMakeLockedRequestContextFixture()

    return AiChatRequest(
        context: AiChatRequestContextSnapshot(
            requestID: AiChatRequestID(rawValue: providerExecutionMakeUUID("00000000-0000-0000-0000-000000000001")),
            runID: AiChatRunID(rawValue: providerExecutionMakeUUID("00000000-0000-0000-0000-000000000002")),
            provider: .openai,
            model: AiModelHandle(provider: .openai, rawValue: "gpt-5.5"),
            selectedModel: selectedModel,
            selectedThinking: .effort(.high),
            sessionStatus: .idle,
            currentContext: AiChatCurrentContextSnapshot(
                summary: "live workspace context",
                attachments: [
                    AiChatContextAttachment(
                        identifier: "live-attachment",
                        title: "Should not leak live attachment",
                    ),
                ],
            ),
            requestContext: lockedRequestContext,
            promptSummary: "summarized prompt",
            submittedAtMs: 1234,
        ),
        messages: [
            AiChatMessage(role: .system, content: "System rule"),
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "Previous answer"),
        ],
    )
}

func providerExecutionMakeAnthropicPreparedRequestFixture(
    selectedThinking: AiThinkingSelection? = .effort(.high),
    capability: AiModelThinkingCapability = .adaptive(effortValues: [.low, .high], defaultValue: .low),
    supportsThinkingNone: Bool = false,
) -> AiChatRequest {
    let selectedModel = AiProviderModel(
        id: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-6"),
        provider: .anthropic,
        rawModelID: "claude-sonnet-4-6",
        displayName: "Claude Sonnet 4.6",
        providerDisplayName: "Anthropic",
        thinkingCapability: capability,
        supportsThinkingNone: supportsThinkingNone,
        unavailableReason: nil,
    )

    let lockedRequestContext = providerExecutionMakeLockedRequestContextFixture()

    return AiChatRequest(
        context: AiChatRequestContextSnapshot(
            requestID: AiChatRequestID(rawValue: providerExecutionMakeUUID("00000000-0000-0000-0000-000000000101")),
            runID: AiChatRunID(rawValue: providerExecutionMakeUUID("00000000-0000-0000-0000-000000000102")),
            provider: .anthropic,
            model: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-6"),
            selectedModel: selectedModel,
            selectedThinking: selectedThinking,
            sessionStatus: .idle,
            currentContext: AiChatCurrentContextSnapshot(
                summary: "live workspace context",
                references: [
                    AiChatContextReference(
                        kind: .file,
                        identifier: "/tmp/workspace/Live.swift",
                        title: "Live.swift",
                    ),
                ],
            ),
            requestContext: lockedRequestContext,
            promptSummary: "anthropic prompt summary",
            submittedAtMs: 2345,
        ),
        messages: [
            AiChatMessage(role: .system, content: "Answer briefly"),
            AiChatMessage(role: .user, content: "Say hi"),
            AiChatMessage(role: .assistant, content: "Previous reply"),
        ],
    )
}

func providerExecutionMakeLockedRequestContextFixture() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: providerExecutionMakeLockedCurrentContextFixture(),
        addedAttachments: providerExecutionMakeLockedAttachmentSnapshotFixtures(),
    )
}

func providerExecutionMakeLockedCurrentContextFixture() -> AiChatCurrentContextSnapshot {
    AiChatCurrentContextSnapshot(
        summary: "locked workspace context",
        references: [
            AiChatContextReference(
                kind: .file,
                identifier: "/tmp/workspace/File.swift",
                title: "File.swift",
            ),
        ],
        items: [
            AiChatContextItem(
                kind: .file,
                identifier: "item-1",
                title: "Notes.md",
                subtitle: "/tmp/workspace/Notes.md",
                references: [
                    AiChatContextReference(
                        kind: .selection,
                        identifier: "selection-1",
                        title: "Selected lines 1-4",
                    ),
                ],
            ),
        ],
        attachments: [
            AiChatContextAttachment(identifier: "attachment-1", title: "Screenshot"),
        ],
    )
}

func providerExecutionMakeLockedAttachmentSnapshotFixtures() -> [AiChatAttachmentSnapshot] {
    [
        AiChatAttachmentSnapshot(
            id: AiChatAttachmentID(rawValue: "attachment-text"),
            source: .file,
            displayTitle: "Notes.txt",
            subtitle: "Locked note",
            kind: .file,
            sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/workspace/Notes.txt"),
            metadata: ["mimeType": "text/plain"],
            resolutionResult: .resolvedText(
                text: "Attachment body from locked snapshot",
                metadata: ["encoding": "utf-8"],
            ),
        ),
        AiChatAttachmentSnapshot(
            id: AiChatAttachmentID(rawValue: "attachment-reference"),
            source: .collectionDocument,
            displayTitle: "Workspace.voycoll",
            kind: .file,
            sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/workspace/Workspace.voycoll"),
            metadata: ["mimeType": "application/x-voycoll"],
            resolutionResult: .resolvedReference(metadata: ["resolution": "reference_only"]),
        ),
        AiChatAttachmentSnapshot(
            id: AiChatAttachmentID(rawValue: "attachment-too-large"),
            source: .file,
            displayTitle: "Large.bin",
            kind: .file,
            sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/workspace/Large.bin"),
            metadata: ["mimeType": "application/octet-stream"],
            resolutionResult: .failure(reason: .tooLarge, metadata: ["limitBytes": "65536"]),
        ),
        AiChatAttachmentSnapshot(
            id: AiChatAttachmentID(rawValue: "attachment-unsupported"),
            source: .file,
            displayTitle: "Unsupported.bin",
            kind: .file,
            sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/workspace/Unsupported.bin"),
            metadata: ["mimeType": "application/octet-stream"],
            resolutionResult: .failure(
                reason: .unsupportedType,
                metadata: ["detectedType": "application/octet-stream"],
            ),
        ),
    ]
}

func providerExecutionConsumeUntilCancelled(
    _ stream: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>,
    startedObserved: XCTestExpectation,
    finished: XCTestExpectation,
) -> Task<[AiChatProviderExecutionEvent], Never> {
    Task {
        defer { finished.fulfill() }
        return await providerExecutionCollectUntilCancelled(stream, startedObserved: startedObserved)
    }
}

func providerExecutionCollectUntilCancelled(
    _ stream: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>,
    startedObserved: XCTestExpectation,
) async -> [AiChatProviderExecutionEvent] {
    var events: [AiChatProviderExecutionEvent] = []
    do {
        for try await event in stream {
            events.append(event)
            if case .started = event { startedObserved.fulfill() }
        }
    } catch is CancellationError {
        return events
    } catch {
        XCTFail("Unexpected consumer error: \(error)")
    }
    return events
}

func providerExecutionWaitForCancellation(onCancel: @escaping @Sendable () -> Void) async throws -> String {
    try await withTaskCancellationHandler {
        while !Task.isCancelled {
            await Task.yield()
        }
        throw CancellationError()
    } onCancel: {
        onCancel()
    }
}

func providerExecutionCancellableRegistryStream(
    context: AiChatRequestContextSnapshot,
    producerEntered: XCTestExpectation,
    producerCancelled: XCTestExpectation,
) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
    AsyncThrowingStream { continuation in
        let producer = Task {
            await withTaskCancellationHandler {
                producerEntered.fulfill()
                continuation.yield(.started(context: context))
                while !Task.isCancelled {
                    await Task.yield()
                }
                continuation.finish()
            } onCancel: {
                producerCancelled.fulfill()
                continuation.finish()
            }
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination { producer.cancel() }
        }
    }
}

extension [AiChatProviderExecutionEvent] {
    var providerExecutionContainsTerminalEvent: Bool {
        contains { event in
            if case .final = event { return true }
            if case .failed = event { return true }
            return false
        }
    }
}
