import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
// swiftlint:disable:next type_body_length
final class AiChatFeatureEntryStateTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testSetupBuildsUnconnectedEntryStateWithSkeletonDisplayContract() async {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()

        await store.send(.setup(AiChatSetupState(
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil
        ))) { state in
            state.sessionID = nil
            state.sessionStatus = .idle
            state.currentContext = summary
            state.transcriptHistory = []
            state.draftText = ""
            state.catalogRows = catalogRows
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        await store.send(.onAppear)

        XCTAssertEqual(store.state.currentContextSummaryDisplayModel.title, "Four files selected")
        XCTAssertEqual(store.state.currentContextSummaryDisplayModel.detail, "1 reference · 1 item · 1 attachment")
        XCTAssertEqual(store.state.connectionState, .unconnected(.init(
            title: "Connect an AI provider",
            detail: "Set up a provider in Settings to chat with this context.",
            fixLabel: "Open Settings"
        )))

        if case let .unconnected(connection, summaryDisplay) = store.state.surfaceState {
            XCTAssertEqual(connection.fixLabel, "Open Settings")
            XCTAssertEqual(summaryDisplay.title, "Four files selected")
        } else {
            XCTFail("Expected unconnected surface state")
        }

        XCTAssertEqual(store.state.skeletonDisplayModel.headerTitle, "Chat")
        XCTAssertEqual(store.state.chatInputDisplayModel.placeholder, "Ask anything…")
        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, "Select model")
        XCTAssertEqual(store.state.chatInputDisplayModel.effortLabel, "Select model")
        XCTAssertFalse(store.state.chatInputDisplayModel.canSubmit)
        XCTAssertFalse(store.state.canSubmit)

        XCTAssertEqual(store.state.modelFieldLabel, "Model")
        XCTAssertEqual(store.state.modelCatalogState.rows.first?.label.title, "GPT-4.1 Mini")
        XCTAssertNil(store.state.modelCatalogState.rows.first?.label.subtitle)
        XCTAssertNil(store.state.modelCatalogState.rows.first?.providerBadge)
        XCTAssertNil(store.state.selectedModelDisplayModel)
        XCTAssertNil(store.state.selectedModelHandle)
    }

    func testChatInputThinkingLabelReflectsUnknownUnsupportedAndSupportedCapabilities() {
        let selectedHandle = makeCatalogRows()[0].handle
        let unknownState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: selectedHandle
        )
        let unsupportedModel = AiProviderModel(
            id: selectedHandle,
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            displayName: "GPT-4.1 Mini",
            providerDisplayName: ProviderDescriptor.descriptor(for: .openai)?.displayName ?? "OpenAI",
            thinkingCapability: .unsupported(reason: .init(message: "Thinking is not supported for this model.")),
            unavailableReason: nil
        )
        let unsupportedState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded([unsupportedModel]),
            selectedModelHandle: selectedHandle
        )
        let supportedState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: selectedHandle
        )

        XCTAssertEqual(unknownState.chatInputDisplayModel.effortLabel, "Thinking unavailable")
        XCTAssertEqual(unsupportedState.chatInputDisplayModel.effortLabel, "Thinking unavailable")
        XCTAssertEqual(supportedState.chatInputDisplayModel.effortLabel, "default")
    }

    func testModelSelectorContentStateProvidesExplicitNonLoadedStates() {
        let loadingState = AiChatFeature.State(modelListState: .loading)
        let emptyState = AiChatFeature.State(modelListState: .empty)
        let failedState = AiChatFeature.State(modelListState: .failed(.init(
            message: "Anthropic model list request failed (500)."
        )))
        let unsupportedState = AiChatFeature.State(modelListState: .failed(.init(
            message: "ChatGPT Codex model listing is unavailable.",
            reason: .unsupportedProvider
        )))

        XCTAssertTrue(loadingState.modelSelectorHasPresentableContent)
        XCTAssertFalse(loadingState.modelSelectorIsDisabled)
        XCTAssertFalse(AiChatModelSelectorLayout.usesScrollableContent(for: loadingState.modelSelectorContentState))
        XCTAssertEqual(loadingState.modelSelectorContentState, .loading(.init(
            title: "Loading models",
            detail: "Fetching available models from connected providers."
        )))

        XCTAssertTrue(emptyState.modelSelectorHasPresentableContent)
        XCTAssertTrue(emptyState.modelSelectorIsDisabled)
        XCTAssertFalse(AiChatModelSelectorLayout.usesScrollableContent(for: emptyState.modelSelectorContentState))
        XCTAssertEqual(emptyState.modelSelectorContentState, .empty(.init(
            title: "No models available",
            detail: "No selectable models are available for the current provider setup."
        )))

        XCTAssertTrue(failedState.modelSelectorHasPresentableContent)
        XCTAssertFalse(failedState.modelSelectorIsDisabled)
        XCTAssertFalse(AiChatModelSelectorLayout.usesScrollableContent(for: failedState.modelSelectorContentState))
        XCTAssertEqual(failedState.modelSelectorContentState, .failed(.init(
            title: "Models unavailable",
            detail: "Anthropic model list request failed (500)."
        )))

        XCTAssertTrue(unsupportedState.modelSelectorHasPresentableContent)
        XCTAssertFalse(unsupportedState.modelSelectorIsDisabled)
        XCTAssertFalse(AiChatModelSelectorLayout.usesScrollableContent(for: unsupportedState.modelSelectorContentState))
        XCTAssertEqual(unsupportedState.modelSelectorContentState, .unsupported(.init(
            title: "Provider unsupported",
            detail: "ChatGPT Codex model listing is unavailable."
        )))
    }

    func testModelSelectorContentStateGroupsLoadedModelsByProviderWithoutConnectionSnapshot() {
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(makeProviderModels()),
            providerConnectionSnapshot: .unknown,
            availableModelsByProvider: [:]
        )

        guard case let .loaded(sections) = state.modelSelectorContentState else {
            return XCTFail("Expected loaded model selector content")
        }

        XCTAssertEqual(sections.map(\.title), [
            aiChatProviderSectionTitle(for: .openai),
            aiChatProviderSectionTitle(for: .anthropic)
        ])
        XCTAssertEqual(sections.first?.rows.map(\.title), ["GPT-4.1 Mini"])
        XCTAssertEqual(sections.last?.rows.map(\.title), ["Claude Sonnet 4"])
        XCTAssertTrue(state.modelSelectorHasPresentableContent)
        XCTAssertFalse(state.modelSelectorIsDisabled)
        XCTAssertTrue(AiChatModelSelectorLayout.usesScrollableContent(for: state.modelSelectorContentState))
        XCTAssertGreaterThan(AiChatModelSelectorLayout.contentMaxHeight, 0)
    }

    func testModelSelectorLabelUsesSelectedModelDisplayNameWhenLoaded() {
        let catalogRows = makeCatalogRows()
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[1].handle
        )

        XCTAssertEqual(AiChatSelectorLabels.modelSelectorLabel(for: state), "Claude Sonnet 4")
    }

    func testModelSelectorLabelFallsBackToGenericLoadedLabelWithoutSelection() {
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: nil
        )

        XCTAssertEqual(AiChatSelectorLabels.modelSelectorLabel(for: state), "Model")
    }

    func testCurrentContextSummaryFixturesMatchInspectorContract() {
        let selectedHandle = makeCatalogRows()[0].handle

        let selectedEntriesState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(
                summary: "Documents · 2 selected",
                references: [],
                items: [],
                attachments: []
            ),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )
        XCTAssertEqual(selectedEntriesState.currentContextSummaryDisplayModel.title, "Documents · 2 selected")
        XCTAssertNil(selectedEntriesState.currentContextSummaryDisplayModel.detail)

        let locationOnlyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )
        XCTAssertEqual(locationOnlyState.currentContextSummaryDisplayModel.title, "Documents")
        XCTAssertNil(locationOnlyState.currentContextSummaryDisplayModel.detail)

        let emptyContextState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )
        XCTAssertEqual(emptyContextState.currentContextSummaryDisplayModel.title, "No current selection")
        XCTAssertNil(emptyContextState.currentContextSummaryDisplayModel.detail)
    }

    func testProviderUnavailableSurfaceUsesFixedBannerAndEmptyComposerModelLabel() {
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )

        XCTAssertEqual(state.connectionState, .connected)
        XCTAssertFalse(state.canSubmit)
        XCTAssertEqual(state.chatInputDisplayModel.modelLabel, "No models available")
        XCTAssertEqual(state.chatInputDisplayModel.effortLabel, "No models available")

        if case let .empty(summary, selectedModel) = state.surfaceState {
            XCTAssertNil(selectedModel)
            XCTAssertEqual(summary.title, "Documents")
        } else {
            XCTFail("Expected empty surface with no loaded models")
        }
    }

    func testCanSubmitDisallowsRetryWhileFailureSurfaceExists() {
        let catalogRows = makeCatalogRows()
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Retry after failure",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: .transportError,
            executionPhase: .idle
        )
        let store = TestStore(initialState: state) {
            AiChatFeature()
        }
        XCTAssertFalse(store.state.canSubmit)
    }

    func testSubmitTappedIsNoOpWhenCanSubmitIsFalse() async {
        final class ExecutionRequestSpy: @unchecked Sendable {
            private(set) var requests: [AiChatRequest] = []

            func append(_ request: AiChatRequest) {
                requests.append(request)
            }
        }

        let requestSpy = ExecutionRequestSpy()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                requestSpy.append(request)
                return AsyncStream { continuation in
                    continuation.finish()
                }
            })
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.submitTapped)

        XCTAssertTrue(requestSpy.requests.isEmpty)
        XCTAssertEqual(store.state.draftText, "Hello")
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)

        await store.finish()
    }
}
