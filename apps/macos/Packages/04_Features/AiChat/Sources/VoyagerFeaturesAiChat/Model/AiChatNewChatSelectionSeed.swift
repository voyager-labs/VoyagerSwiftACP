import Foundation
import VoyagerEntitiesAi

public struct AiChatNewChatSelectionCandidate: Equatable, Sendable {
    public let modelHandle: AiModelHandle
    public let selectedThinking: AiThinkingSelection?

    public init(modelHandle: AiModelHandle, selectedThinking: AiThinkingSelection?) {
        self.modelHandle = modelHandle
        self.selectedThinking = selectedThinking
    }
}

public enum AiChatPersistedThinkingSelection: Equatable, Sendable {
    case providerDefault
    case none
    case effort(String)
    case tokenBudget(Int)
}

public struct AiChatPersistedSelectionCandidate: Equatable, Sendable {
    public let providerRawValue: String?
    public let modelProviderRawValue: String?
    public let modelRawValue: String?
    public let thinking: AiChatPersistedThinkingSelection

    public init(
        providerRawValue: String?,
        modelProviderRawValue: String?,
        modelRawValue: String?,
        thinking: AiChatPersistedThinkingSelection,
    ) {
        self.providerRawValue = providerRawValue
        self.modelProviderRawValue = modelProviderRawValue
        self.modelRawValue = modelRawValue
        self.thinking = thinking
    }
}

public struct AiChatNewChatSelectionSeed: Equatable, Sendable {
    public let modelHandle: AiModelHandle
    public let selectedThinking: AiThinkingSelection?

    public init(modelHandle: AiModelHandle, selectedThinking: AiThinkingSelection?) {
        self.modelHandle = modelHandle
        self.selectedThinking = selectedThinking
    }
}

/// 비동기 New Chat 준비가 시작된 뒤 사용자 또는 navigation state가 바뀌지 않았는지 검증하는 값입니다.
/// FileManager가 동일 snapshot을 child action까지 전달해야 하므로 public이며, 생성은 `AiChatState`가 소유합니다.
public struct AiChatNewChatPreparationProvenance: Equatable, Sendable {
    let ownerID: UUID
    let mutationRevision: UInt64
    let restoreSessionID: AiChatSessionID?
    let deferredChatSessionRestoreID: AiChatSessionID?
    let restoreOutcome: AiChatSessionRestoreResult?
    let restoreFailure: AiChatSessionRestoreFailure?
    let mode: AiChatMode
    let selectedHistorySessionID: AiChatSessionID?
    let sessionID: AiChatSessionID?
    let preparedTransientSessionID: AiChatSessionID?
    let emptyDraftSessionID: AiChatSessionID?
    let currentSessionCustomTitle: String?
    let sessionStatus: AiChatSessionStatus
    let currentContext: AiChatCurrentContextSnapshot
    let currentContextFolderStructureModes: AiChatCurrentContextFolderStructureModes
    let addedAttachments: [AiChatAttachmentDraft]
    let transcriptHistory: [AiChatMessage]
    let draftText: String
    let streamingAssistantDraft: String?
    let selectedModelHandle: AiModelHandle?
    let selectedThinking: AiThinkingSelection?
    let unavailableSelectedModelHandle: AiModelHandle?
    let pendingRequestStart: AiChatPendingRequestStart?
    let executionPhase: AiChatExecutionPhase
}

public enum AiChatNewChatSelectionSeedResolver {
    public static func resolve(
        windowLast: AiChatNewChatSelectionCandidate?,
        persistedDefault: AiChatPersistedSelectionCandidate?,
        state: AiChatFeature.State,
    ) -> AiChatNewChatSelectionSeed? {
        if let windowLast, let seed = resolve(windowLast, state: state) {
            return seed
        }
        guard let persistedDefault,
              let candidate = runtimeCandidate(from: persistedDefault)
        else { return nil }
        return resolve(candidate, state: state)
    }

    public static func resolve(
        windowLast: AiChatNewChatSelectionCandidate?,
        persistedDefault: AiChatPersistedSelectionCandidate?,
        catalog: [AiProviderModel],
    ) -> AiChatNewChatSelectionSeed? {
        if let windowLast, let seed = resolve(windowLast, catalog: catalog) {
            return seed
        }
        guard let persistedDefault,
              let candidate = runtimeCandidate(from: persistedDefault)
        else { return nil }
        return resolve(candidate, catalog: catalog)
    }

    static func revalidate(
        _ seed: AiChatNewChatSelectionSeed?,
        catalog: [AiProviderModel],
    ) -> AiChatNewChatSelectionSeed? {
        guard let seed else { return nil }
        return resolve(
            AiChatNewChatSelectionCandidate(
                modelHandle: seed.modelHandle,
                selectedThinking: seed.selectedThinking,
            ),
            catalog: catalog,
        )
    }

    private static func resolve(
        _ candidate: AiChatNewChatSelectionCandidate,
        state: AiChatFeature.State,
    ) -> AiChatNewChatSelectionSeed? {
        AiChatStateSelection.revalidatedNewChatSelectionSeed(
            AiChatNewChatSelectionSeed(
                modelHandle: candidate.modelHandle,
                selectedThinking: candidate.selectedThinking,
            ),
            state: state,
        )
    }

    private static func resolve(
        _ candidate: AiChatNewChatSelectionCandidate,
        catalog: [AiProviderModel],
    ) -> AiChatNewChatSelectionSeed? {
        guard let model = AiChatStateSelection.resolvedModel(
            for: candidate.modelHandle,
            in: catalog,
        ) else { return nil }
        return AiChatNewChatSelectionSeed(
            modelHandle: model.id,
            selectedThinking: AiThinkingSelectionPolicy.normalize(
                candidate.selectedThinking,
                capability: model.thinkingCapability,
                supportsNone: model.supportsThinkingNone,
            ),
        )
    }

    private static func runtimeCandidate(
        from candidate: AiChatPersistedSelectionCandidate,
    ) -> AiChatNewChatSelectionCandidate? {
        guard let providerRawValue = candidate.providerRawValue,
              let modelProviderRawValue = candidate.modelProviderRawValue,
              providerRawValue == modelProviderRawValue,
              let provider = AiProvider(rawValue: providerRawValue),
              let modelRawValue = candidate.modelRawValue
        else { return nil }

        return AiChatNewChatSelectionCandidate(
            modelHandle: AiModelHandle(provider: provider, rawValue: modelRawValue),
            selectedThinking: runtimeThinking(from: candidate.thinking),
        )
    }

    private static func runtimeThinking(
        from selection: AiChatPersistedThinkingSelection,
    ) -> AiThinkingSelection? {
        switch selection {
        case .providerDefault:
            nil
        case .none:
            AiThinkingSelection.none
        case let .effort(rawValue):
            AiThinkingEffort(rawValue: rawValue).map(AiThinkingSelection.effort)
        case let .tokenBudget(value):
            .tokenBudget(value)
        }
    }
}
