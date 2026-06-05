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

private struct ProviderExecutionCapturedOpenAIRequestBody: Decodable {
    let model: String
    let input: [ProviderExecutionCapturedOpenAIInputItem]
    let reasoning: ProviderExecutionCapturedOpenAIReasoning?
    let stream: Bool
}

private struct ProviderExecutionCapturedOpenAIInputItem: Decodable {
    let role: String
    let content: ProviderExecutionCapturedOpenAIContent
}

private enum ProviderExecutionCapturedOpenAIContent: Decodable, Equatable {
    case text(String)
    case parts([ProviderExecutionCapturedOpenAIContentItem])

    var text: String? {
        guard case let .text(value) = self else { return nil }
        return value
    }

    var parts: [ProviderExecutionCapturedOpenAIContentItem]? {
        guard case let .parts(value) = self else { return nil }
        return value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = try .parts(container.decode([ProviderExecutionCapturedOpenAIContentItem].self))
    }
}

private struct ProviderExecutionCapturedOpenAIContentItem: Decodable, Equatable {
    let type: String
    let text: String?
    let detail: String?
    let imageURL: String?
    let fileData: String?
    let filename: String?

    init(
        type: String,
        text: String? = nil,
        detail: String? = nil,
        imageURL: String? = nil,
        fileData: String? = nil,
        filename: String? = nil,
    ) {
        self.type = type
        self.text = text
        self.detail = detail
        self.imageURL = imageURL
        self.fileData = fileData
        self.filename = filename
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case detail
        case imageURL = "image_url"
        case fileData = "file_data"
        case filename
    }
}

private struct ProviderExecutionCapturedOpenAIReasoning: Decodable {
    let effort: String?
    let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

private struct ProviderExecutionCapturedAnthropicRequestBody: Decodable {
    let model: String
    let maxTokens: Int
    let messages: [ProviderExecutionCapturedAnthropicMessage]
    let system: String?
    let thinking: ProviderExecutionCapturedAnthropicThinking?
    let outputConfig: ProviderExecutionCapturedAnthropicOutputConfig?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
        case thinking
        case outputConfig = "output_config"
        case stream
    }
}

private struct ProviderExecutionCapturedAnthropicOutputConfig: Decodable {
    let effort: String?
}

private struct ProviderExecutionCapturedAnthropicMessage: Decodable {
    let role: String
    let content: [ProviderExecutionCapturedAnthropicContentItem]
}

private struct ProviderExecutionCapturedAnthropicContentItem: Decodable, Equatable {
    let type: String
    let text: String?
    let source: ProviderExecutionCapturedAnthropicSource?
    let title: String?

    static func text(_ value: String) -> Self {
        .init(type: "text", text: value, source: nil, title: nil)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case title
    }
}

private struct ProviderExecutionCapturedAnthropicSource: Decodable, Equatable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct ProviderExecutionCapturedAnthropicThinking: Decodable {
    let type: String
    let budgetTokens: Int?
    let display: String?

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
        case display
    }
}

enum ProviderExecutionExpectedAnthropicThinking: Equatable {
    case disabled
    case enabled(Int, display: String?)
    case outputConfigEffort(String)
    case adaptive(String, display: String?)
    case omitted
}

final class ProviderExecutionURLProtocol: URLProtocol, @unchecked Sendable {
    private nonisolated(unsafe) static var count = 0
    private nonisolated(unsafe) static var currentHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { currentHandler }
        set { currentHandler = newValue }
    }

    static var requestCount: Int { count }

    static func reset() {
        count = 0
        currentHandler = nil
    }

    override static func canInit(with _: URLRequest) -> Bool {
        count += 1
        return true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func providerExecutionAssertOpenAIRequest(_ request: URLRequest, expectedModel: String) throws {
    XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-openai")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

    let body = try XCTUnwrap(providerExecutionRequestBodyData(for: request))
    let decoded = try JSONDecoder().decode(ProviderExecutionCapturedOpenAIRequestBody.self, from: body)
    XCTAssertEqual(decoded.model, expectedModel)
    XCTAssertTrue(decoded.stream)
    XCTAssertEqual(decoded.reasoning?.effort, "high")
    XCTAssertEqual(decoded.input.map(\.role), ["developer", "developer", "user", "assistant"])
    let prompt = decoded.input.first?.content.text
    XCTAssertEqual(prompt?.contains("current_context:"), true)
    XCTAssertEqual(prompt?.contains("summary: locked workspace context"), true)
    XCTAssertEqual(prompt?.contains("Notes.txt [resolvedText]"), true)
    XCTAssertEqual(prompt?.contains("Attachment body from locked snapshot"), true)
    XCTAssertEqual(prompt?.contains("Workspace.voycoll [resolvedReference]"), true)
    XCTAssertEqual(prompt?.contains("reference included; content not expanded."), true)
    XCTAssertEqual(prompt?.contains("Large.bin [tooLarge]"), true)
    XCTAssertEqual(prompt?.contains("not included: tooLarge"), true)
    XCTAssertEqual(prompt?.contains("Unsupported.bin [unsupportedType]"), true)
    XCTAssertEqual(prompt?.contains("not included: unsupportedType"), true)
    XCTAssertEqual(prompt?.contains("live workspace context"), false)
    XCTAssertEqual(prompt?.contains("Should not leak live attachment"), false)
    XCTAssertEqual(decoded.input[1].content.text, "System rule")
    XCTAssertEqual(decoded.input[2].content.text, "Hello")
    XCTAssertEqual(decoded.input[3].content.text, "Previous answer")
}

func providerExecutionAssertAnthropicRequest(
    _ request: URLRequest,
    expectedModel: String,
    expectedThinking: ProviderExecutionExpectedAnthropicThinking,
) throws {
    XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
    XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

    let body = try XCTUnwrap(providerExecutionRequestBodyData(for: request))
    let decoded = try JSONDecoder().decode(ProviderExecutionCapturedAnthropicRequestBody.self, from: body)
    XCTAssertEqual(decoded.model, expectedModel)
    XCTAssertEqual(decoded.maxTokens, 4096)
    XCTAssertTrue(decoded.stream)
    XCTAssertEqual(decoded.system?.contains("current_context:"), true)
    XCTAssertEqual(decoded.system?.contains("summary: locked workspace context"), true)
    XCTAssertEqual(decoded.system?.contains("Notes.txt [resolvedText]"), true)
    XCTAssertEqual(decoded.system?.contains("Workspace.voycoll [resolvedReference]"), true)
    XCTAssertEqual(decoded.system?.contains("Large.bin [tooLarge]"), true)
    XCTAssertEqual(decoded.system?.contains("Unsupported.bin [unsupportedType]"), true)
    XCTAssertEqual(decoded.system?.contains("live workspace context"), false)
    XCTAssertEqual(decoded.system?.contains("Answer briefly"), true)
    XCTAssertEqual(decoded.messages.map(\.role), ["user", "assistant"])
    XCTAssertEqual(decoded.messages.first?.content, [.text("Say hi")])
    XCTAssertEqual(decoded.messages.last?.content, [.text("Previous reply")])

    switch expectedThinking {
    case .disabled:
        XCTAssertEqual(decoded.thinking?.type, "disabled")
        XCTAssertNil(decoded.thinking?.budgetTokens)
        XCTAssertNil(decoded.thinking?.display)
        XCTAssertNil(decoded.outputConfig)
    case let .enabled(budget, display):
        XCTAssertEqual(decoded.thinking?.type, "enabled")
        XCTAssertEqual(decoded.thinking?.budgetTokens, budget)
        XCTAssertEqual(decoded.thinking?.display, display)
        XCTAssertNil(decoded.outputConfig)
    case let .outputConfigEffort(effort):
        XCTAssertNil(decoded.thinking)
        XCTAssertEqual(decoded.outputConfig?.effort, effort)
    case let .adaptive(effort, display):
        XCTAssertEqual(decoded.thinking?.type, "adaptive")
        XCTAssertNil(decoded.thinking?.budgetTokens)
        XCTAssertEqual(decoded.thinking?.display, display)
        XCTAssertEqual(decoded.outputConfig?.effort, effort)
    case .omitted:
        XCTAssertNil(decoded.thinking)
        XCTAssertNil(decoded.outputConfig)
    }
}

func providerExecutionRequestBodyData(for request: URLRequest) throws -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    defer { buffer.deallocate() }
    var data = Data()

    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: 1024)
        if read < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeRawData)
        }
        if read == 0 { break }
        data.append(buffer, count: read)
    }

    return data
}

func providerExecutionOpenAIStreamingBody() -> String {
    """
    event: response.created
    data: {"type":"response.created"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"Hel"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"lo"}

    event: response.completed
    data: {"type":"response.completed","response":{"output_text":"Hello"}}

    data: [DONE]

    """
}

func providerExecutionOpenAIStreamFailureBody() -> String {
    """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"partial"}

    event: response.failed
    data: {"type":"response.failed","error":{"message":"OpenAI stream failed"}}

    """
}

func providerExecutionOpenAIFinalOnlyBody() -> String {
    #"{"output":[{"content":[{"type":"output_text","text":"Hello"}]}]}"#
}

func providerExecutionAnthropicStreamingBody() -> String {
    """
    event: message_start
    data: {"type":"message_start","message":{"content":[]}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" there"}}

    event: message_stop
    data: {"type":"message_stop"}

    """
}

func providerExecutionAnthropicStreamingBodyWithThinkingAndMessageDelta() -> String {
    """
    event: message_start
    data: {"type":"message_start","message":{"content":[]}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"internal reasoning"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: content_block_start
    data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Final"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" answer"}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":861}}

    event: message_stop
    data: {"type":"message_stop"}

    """
}

func providerExecutionAnthropicStreamErrorBody(type: String) -> String {
    """
    event: error
    data: {"type":"error","error":{"type":"\(type)","message":"anthropic stream failed"}}

    """
}

func providerExecutionAnthropicFinalOnlyBody() -> String {
    #"{"content":[{"type":"text","text":"Hi there"}],"stop_reason":"end_turn"}"#
}

func providerExecutionMakeHTTPResponse(
    statusCode: Int,
    contentType: String,
    body: String,
    url: String = "https://api.openai.com/v1/responses",
) -> (HTTPURLResponse, Data) {
    let resolvedURL = URL(string: url) ?? URL(fileURLWithPath: "/invalid-url")
    let response = HTTPURLResponse(
        url: resolvedURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": contentType],
    ) ?? HTTPURLResponse()
    return (response, Data(body.utf8))
}

func providerExecutionMakeUUID(_ rawValue: String) -> UUID {
    UUID(uuidString: rawValue) ?? UUID()
}

func providerExecutionCollect(
    _ stream: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>,
) throws -> [AiChatProviderExecutionEvent] {
    let expectation = XCTestExpectation(description: "Collect provider execution events")
    nonisolated(unsafe) var result: Result<[AiChatProviderExecutionEvent], Error>?

    Task { @Sendable in
        do {
            var events: [AiChatProviderExecutionEvent] = []
            for try await event in stream {
                events.append(event)
            }
            result = .success(events)
        } catch {
            result = .failure(error)
        }
        expectation.fulfill()
    }

    _ = XCTWaiter.wait(for: [expectation], timeout: 2.0)
    return try XCTUnwrap(result).get()
}
