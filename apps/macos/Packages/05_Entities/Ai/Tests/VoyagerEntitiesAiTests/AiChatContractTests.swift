import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatContractTests: XCTestCase {
    func testAiModelHandle_roundTripsAndPreservesProviderAuthCompatibility() throws {
        let handle = AiModelHandle(provider: .chatgptCodex, rawValue: "gpt-4o-mini")
        let encoded = try JSONEncoder().encode(handle)
        let decoded = try JSONDecoder().decode(AiModelHandle.self, from: encoded)

        XCTAssertEqual(decoded, handle)
        XCTAssertEqual(ProviderDescriptor.descriptor(for: decoded.provider)?.authMethod, .oauth)
    }

    func testAiModelCatalogRow_roundTripsAndUsesExistingProviderAPIs() throws {
        let row = AiModelCatalogRow(
            handle: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            subtitle: "Fast general-purpose chat",
            sortOrder: 10,
            isDefault: true,
            isRecommended: true
        )
        let encoded = try JSONEncoder().encode(row)
        let decoded = try JSONDecoder().decode(AiModelCatalogRow.self, from: encoded)

        XCTAssertEqual(decoded, row)
        XCTAssertEqual(ProviderDescriptor.descriptor(for: decoded.handle.provider)?.authMethod, decoded.authMethod)
    }

    // swiftlint:disable:next function_body_length
    func testRequestContextSnapshot_roundTrips() throws {
        let snapshot = AiChatRequestContextSnapshot(
            sessionID: AiChatSessionID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
            requestID: AiChatRequestID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
            runID: AiChatRunID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
            provider: .anthropic,
            model: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-20250514"),
            selectedModelRow: AiModelCatalogRow(
                handle: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-20250514"),
                displayName: "Claude Sonnet 4",
                authMethod: .apiKey,
                sortOrder: 2
            ),
            sessionStatus: .restoring,
            currentContext: AiChatCurrentContextSnapshot(
                summary: "Four files selected",
                references: [
                    AiChatContextReference(
                        kind: .reference,
                        identifier: "ref-1",
                        title: "Readme.md",
                        subtitle: "Project readme",
                        metadata: ["path": "docs/Readme.md"]
                    )
                ],
                items: [
                    AiChatContextItem(
                        kind: .file,
                        identifier: "file-1",
                        title: "VoyagerEntitiesAi.swift",
                        subtitle: "Source file",
                        metadata: ["path": "Sources/VoyagerEntitiesAi/VoyagerEntitiesAi.swift"],
                        references: [
                            AiChatContextReference(
                                kind: .selection,
                                identifier: "selection-1",
                                title: "Selection",
                                metadata: ["line": "12"]
                            )
                        ]
                    )
                ],
                attachments: [
                    AiChatContextAttachment(
                        identifier: "attachment-1",
                        title: "Screenshot",
                        subtitle: "Current state",
                        metadata: ["mimeType": "image/png"]
                    )
                ]
            ),
            promptSummary: "Summarize the selected files",
            submittedAtMs: 1_700_000_000_000
        )

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AiChatRequestContextSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.provider, .anthropic)
        XCTAssertEqual(decoded.sessionStatus, .restoring)
        XCTAssertEqual(decoded.currentContext.summary, "Four files selected")
        XCTAssertEqual(decoded.currentContext.references.first?.identifier, "ref-1")
        XCTAssertEqual(decoded.currentContext.items.first?.references.first?.kind, .selection)
        XCTAssertEqual(decoded.currentContext.attachments.first?.title, "Screenshot")
    }

    func testSessionSnapshotAndRestoreResult_roundTrips() throws {
        let session = AiChatSessionSnapshot(
            sessionID: AiChatSessionID(rawValue: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!),
            status: .active,
            provider: .openai,
            model: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Summarize the diffs"),
                AiChatMessage(role: .assistant, content: "Here is a summary")
            ],
            lastRequestID: AiChatRequestID(rawValue: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!),
            lastRunID: AiChatRunID(rawValue: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!),
            updatedAtMs: 1_700_000_000_100
        )

        let encodedSession = try JSONEncoder().encode(session)
        let decodedSession = try JSONDecoder().decode(AiChatSessionSnapshot.self, from: encodedSession)
        XCTAssertEqual(decodedSession, session)

        let restored = AiChatSessionRestoreResult.restored(snapshot: session)
        let encodedRestore = try JSONEncoder().encode(restored)
        let decodedRestore = try JSONDecoder().decode(AiChatSessionRestoreResult.self, from: encodedRestore)

        XCTAssertEqual(decodedRestore, restored)
        XCTAssertEqual(decodedSession.transcriptHistory.count, 2)
        XCTAssertEqual(decodedSession.transcriptHistory.first?.role, .user)
    }

    func testSessionStatusAndMessageRoles_coverAllCases() {
        XCTAssertEqual(AiChatSessionStatus.allCases.count, 6)
        XCTAssertEqual(AiChatMessageRole.allCases.count, 4)
        XCTAssertEqual(AiChatExecutionFailure.allCases.count, 12)
        XCTAssertEqual(AiChatSessionRestoreFailure.allCases.count, 5)
    }

    func testChatRequestResponseEvent_roundTrips() throws {
        let context = AiChatRequestContextSnapshot(
            requestID: AiChatRequestID(rawValue: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!),
            runID: AiChatRunID(rawValue: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!),
            provider: .chatgptCodex,
            model: AiModelHandle(provider: .chatgptCodex, rawValue: "codex-cli-chat"),
            sessionStatus: .idle,
            currentContext: AiChatCurrentContextSnapshot(
                summary: "Context locked at submit time",
                items: [
                    AiChatContextItem(
                        kind: .note,
                        identifier: "note-1",
                        title: "Locked context",
                        metadata: ["locked": "true"]
                    )
                ]
            ),
            promptSummary: "Keep it short",
            submittedAtMs: 1_700_000_000_200
        )
        let request = AiChatRequest(
            context: context,
            messages: [
                AiChatMessage(role: .system, content: "You are helpful."),
                AiChatMessage(role: .user, content: "Hello")
            ]
        )
        let response = AiChatResponse(
            context: context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Hi there"),
            completedAtMs: 1_700_000_000_300
        )
        let events: [AiChatEvent] = [
            .started(context: context),
            .delta(context: context, text: "Hi"),
            .final(response: response),
            .failed(context: context, reason: .transportError)
        ]

        XCTAssertEqual(try JSONDecoder().decode(AiChatRequest.self, from: JSONEncoder().encode(request)), request)
        XCTAssertEqual(try JSONDecoder().decode(AiChatResponse.self, from: JSONEncoder().encode(response)), response)
        for event in events {
            XCTAssertEqual(try JSONDecoder().decode(AiChatEvent.self, from: JSONEncoder().encode(event)), event)
        }
    }

    func testExecutionFailure_roundTripsAllCases() throws {
        for failure in AiChatExecutionFailure.allCases {
            XCTAssertEqual(
                try JSONDecoder().decode(AiChatExecutionFailure.self, from: JSONEncoder().encode(failure)),
                failure
            )
        }
    }

    func testSendableIntent_isExpressibleAtCompileTime() {
        let request = AiChatRequest(
            context: AiChatRequestContextSnapshot(
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                provider: .openai,
                model: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
                sessionStatus: .active,
                currentContext: AiChatCurrentContextSnapshot(
                    summary: "Current context payload",
                    references: [
                        AiChatContextReference(
                            kind: .attachment,
                            identifier: "attachment-2",
                            title: "Design sketch"
                        )
                    ]
                )
            ),
            messages: []
        )

        _assertSendable(request)
        _assertSendable(AiChatSessionSnapshot(
            sessionID: AiChatSessionID(rawValue: UUID()),
            status: .idle,
            provider: .openai,
            model: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hi")],
            updatedAtMs: 0
        ))
        _assertSendable(TestExecutionClient())
        _assertSendable(TestPersistenceClient())
    }
}

private func _assertSendable<T: Sendable>(_ value: T) {
    _ = value
}

private struct TestExecutionClient: AiChatExecutionClientProtocol {
    func execute(_ request: AiChatRequest) -> AsyncStream<AiChatEvent> {
        AsyncStream { continuation in
            continuation.yield(.started(context: request.context))
            continuation.finish()
        }
    }
}

private struct TestPersistenceClient: AiChatSessionPersistenceClientProtocol {
    func loadSession(id _: AiChatSessionID) async -> AiChatSessionSnapshot? { nil }
    func saveSession(_: AiChatSessionSnapshot) async {}
    func deleteSession(id _: AiChatSessionID) async {}
}
