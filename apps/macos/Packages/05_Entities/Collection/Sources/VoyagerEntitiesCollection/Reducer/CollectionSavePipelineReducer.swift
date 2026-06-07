import ComposableArchitecture
import Foundation
import VoyagerShared

@Reducer
public struct CollectionSavePipelineReducer {
    public typealias State = CollectionState
    public typealias Action = CollectionAction

    @Dependency(\.collectionFileClient)
    var collectionFileClient

    @Dependency(\.collectionSavePanelClient)
    var collectionSavePanelClient

    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    @Dependency(\.collectionStalenessClient)
    var collectionStalenessClient

    @Dependency(\.collectionMetricClient)
    var collectionMetricClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .saveRequested(payload):
                handleSaveRequested(
                    state: &state,
                    payload: payload,
                    collectionSavePanelClient: collectionSavePanelClient,
                    collectionMetricClient: collectionMetricClient,
                )

            case let .saveToExisting(payload, url):
                handleSaveToExisting(
                    state: &state,
                    payload: payload,
                    url: url,
                    collectionFileClient: collectionFileClient,
                    collectionStalenessClient: collectionStalenessClient,
                    collectionMetricClient: collectionMetricClient,
                )

            case let .savePanelResponse(url):
                handleSavePanelResponse(
                    state: &state,
                    selectedURL: url,
                    collectionFileClient: collectionFileClient,
                    collectionStalenessClient: collectionStalenessClient,
                    collectionMetricClient: collectionMetricClient,
                )

            case let .saveCompleted(result):
                handleSaveCompleted(
                    state: &state,
                    result: result,
                    userDefaultsClient: userDefaultsClient,
                    collectionStalenessClient: collectionStalenessClient,
                )

            default:
                .none
            }
        }
    }
}

enum CollectionSaveValidationError: LocalizedError {
    case emptyContent
    case incompleteCondition(String)
    case invalidConditionValue(String)
    case saveBlockedFutureMinor

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Add a query, scope, or condition before saving."
        case let .incompleteCondition(label):
            return "Complete the filter for \"\(label)\" before saving."
        case let .invalidConditionValue(label):
            if label.isEmpty {
                return "Some filter values are invalid."
            }
            return "Check the value for \"\(label)\" before saving."
        case .saveBlockedFutureMinor:
            return "Collections opened from a newer minor schema version are read-only and cannot be saved."
        }
    }
}

private struct CollectionSaveFailure: Equatable, Error {
    let feedback: CollectionSaveFeedback
    let reason: String

    var title: String {
        feedback.title
    }

    var message: String {
        feedback.message
    }
}

private func validateSavePayload(
    _ payload: SaveRequestPayload,
) -> Result<(snapshot: CollectionSaveSnapshot, context: CollectionContext), CollectionSaveFailure> {
    guard let context = payload.context else {
        return .failure(.init(
            feedback: .init(
                stage: .saveBlocked,
                category: .emptyContent,
                title: "No New Collection",
                message: "There is no active new collection to save.",
                recoveryHint: "Add a query, scope, or filter before saving.",
                isRetryable: false,
            ),
            reason: "empty_content",
        ))
    }

    let trimmedQuery = context.query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    let validation = validateCollectionContext(
        context,
        query: trimmedQuery,
        payload: payload,
    )

    switch validation {
    case let .failure(error):
        return .failure(.init(
            feedback: makeValidationFeedback(for: error),
            reason: CollectionFilterSaveMetrics.reason(for: error),
        ))
    case let .success(snapshot):
        return .success((snapshot: snapshot, context: context))
    }
}

private func makeValidationFeedback(for error: CollectionSaveValidationError) -> CollectionSaveFeedback {
    switch error {
    case .emptyContent:
        .init(
            stage: .saveBlocked,
            category: .emptyContent,
            title: "No New Collection",
            message: "There is no active new collection to save.",
            recoveryHint: "Add a query, scope, or filter before saving.",
            isRetryable: false,
        )
    case let .incompleteCondition(label):
        .init(
            stage: .saveBlocked,
            category: .incompleteCondition,
            title: "Unable to Save Collection",
            message: "Complete the filter for \"\(label)\" before saving.",
            recoveryHint: "Fix the highlighted filter and try again.",
            propertyLabel: label,
            isRetryable: false,
        )
    case let .invalidConditionValue(label):
        .init(
            stage: .saveBlocked,
            category: .invalidConditionValue,
            title: "Unable to Save Collection",
            message: label
                .isEmpty ? "Some filter values are invalid." : "Check the value for \"\(label)\" before saving.",
            recoveryHint: "Correct the invalid value and try again.",
            propertyLabel: label,
            isRetryable: false,
        )
    case .saveBlockedFutureMinor:
        .init(
            stage: .saveBlocked,
            category: .futureMinorReadOnly,
            title: "Unable to Save Collection",
            message: "Collections opened from a newer minor schema version are read-only and cannot be saved.",
            recoveryHint: "Open the collection in the matching app version or make a writable copy.",
            isRetryable: false,
        )
    }
}

private func validateCollectionContext(
    _ context: CollectionContext,
    query: String,
    payload: SaveRequestPayload,
) -> Result<CollectionSaveSnapshot, CollectionSaveValidationError> {
    if query.isEmpty, context.scopes.isEmpty, context.conditions.isEmpty {
        return .failure(.emptyContent)
    }

    if payload.openedCompatibility?.writeBackReason == .blockedFutureMinorVersion {
        return .failure(.saveBlockedFutureMinor)
    }

    do {
        let conditions = try buildCollectionConditions(from: context.conditions)
        return .success(.init(
            query: query,
            scopes: context.scopes,
            excludedScopes: context.excludedScopes,
            includeSubfolders: context.includeSubfolders,
            includeDirectories: context.includeDirectories,
            conditions: conditions,
            snapshotItems: payload.snapshotItems,
            definitionFingerprint: payload.definitionFingerprint,
            capturedAt: payload.capturedAt,
            relevanceRoots: payload.relevanceRoots,
        ))
    } catch let error as CollectionSaveValidationError {
        return .failure(error)
    } catch {
        return .failure(.invalidConditionValue(""))
    }
}

private func buildCollectionConditions(from conditions: [Condition]) throws -> [CollectionCondition] {
    var results: [CollectionCondition] = []
    results.reserveCapacity(conditions.count)

    for condition in conditions {
        guard condition.isActive else { continue }
        guard let op = condition.operatorCode, let arity = condition.operatorValueArity else {
            throw CollectionSaveValidationError.incompleteCondition(condition.propertyLabel)
        }

        if arity == 0 {
            results.append(.init(propertyKey: condition.propertyKey, operatorCode: op, value: nil))
            continue
        }

        guard let values = condition.values, values.count >= arity else {
            throw CollectionSaveValidationError.incompleteCondition(condition.propertyLabel)
        }

        guard let encoded = ConditionValueEncoder.encode(condition: condition, values: values) else {
            throw CollectionSaveValidationError.invalidConditionValue(condition.propertyLabel)
        }

        results.append(.init(propertyKey: condition.propertyKey, operatorCode: op, value: encoded))
    }

    return results
}

private func resetPendingSave(_ state: inout CollectionState) {
    state.isSaving = false
    state.pendingSave = nil
    state.pendingSaveContext = nil
}

private func canStartSave(
    state: CollectionState,
    payload: SaveRequestPayload,
) -> Bool {
    guard !state.isSaving else { return false }
    guard !payload.isSearchLoading, !payload.isFiltersLoading else { return false }
    return true
}

private func handleSaveRequested(
    state: inout CollectionState,
    payload: SaveRequestPayload,
    collectionSavePanelClient: CollectionSavePanelClient,
    collectionMetricClient: CollectionMetricClient,
) -> Effect<CollectionAction> {
    let source = "save_new"
    guard canStartSave(state: state, payload: payload) else {
        logCollectionSaveResult(
            outcome: "save_blocked",
            reason: CollectionFilterSaveMetrics.reasonForInFlightBlock(state: state, payload: payload),
            source: source,
            payload: payload,
            collectionMetricClient: collectionMetricClient,
            level: .warn,
        )
        return .none
    }

    switch validateSavePayload(payload) {
    case let .failure(failure):
        logCollectionSaveResult(
            outcome: "save_blocked",
            reason: failure.reason,
            source: source,
            payload: payload,
            collectionMetricClient: collectionMetricClient,
            level: .warn,
        )
        return showSaveError(failure)
    case let .success(result):
        state.pendingSave = result.snapshot
        state.pendingSaveContext = result.context
        state.isSaving = true
        return .run { send in
            let initialDirectory = await collectionSavePanelClient.defaultSaveDirectory(
                result.context.scopes,
            )
            let url = await collectionSavePanelClient.presentSavePanel(
                initialDirectory,
            )
            await send(.savePanelResponse(url))
        }
    }
}

private func handleSaveToExisting(
    state: inout CollectionState,
    payload: SaveRequestPayload,
    url: URL,
    collectionFileClient: CollectionFileClient,
    collectionStalenessClient: CollectionStalenessClient,
    collectionMetricClient: CollectionMetricClient,
) -> Effect<CollectionAction> {
    let source = state.collectionSession.phase.isInflightWriteBack ? "write_back" : "save_existing"
    guard canStartSave(state: state, payload: payload) else {
        logCollectionSaveResult(
            outcome: "save_blocked",
            reason: CollectionFilterSaveMetrics.reasonForInFlightBlock(state: state, payload: payload),
            source: source,
            payload: payload,
            collectionMetricClient: collectionMetricClient,
            level: .warn,
        )
        return .none
    }

    switch validateSavePayload(payload) {
    case let .failure(failure):
        logCollectionSaveResult(
            outcome: "save_blocked",
            reason: failure.reason,
            source: source,
            payload: payload,
            collectionMetricClient: collectionMetricClient,
            level: .warn,
        )
        return showSaveError(failure)
    case let .success(result):
        state.isSaving = true
        return performSave(
            snapshot: result.snapshot,
            savedContext: result.context,
            url: url,
            collectionFileClient: collectionFileClient,
            collectionStalenessClient: collectionStalenessClient,
            collectionMetricClient: collectionMetricClient,
            source: source,
        )
    }
}

private func handleSavePanelResponse(
    state: inout CollectionState,
    selectedURL: URL?,
    collectionFileClient: CollectionFileClient,
    collectionStalenessClient: CollectionStalenessClient,
    collectionMetricClient: CollectionMetricClient,
) -> Effect<CollectionAction> {
    guard let selectedURL,
          let snapshot = state.pendingSave,
          let savedContext = state.pendingSaveContext
    else {
        if let pendingSave = state.pendingSave {
            logCollectionSaveResult(
                outcome: "cancelled",
                reason: "none",
                source: "save_new",
                snapshot: pendingSave,
                collectionMetricClient: collectionMetricClient,
            )
        }
        resetPendingSave(&state)
        return .none
    }

    return performSave(
        snapshot: snapshot,
        savedContext: savedContext,
        url: selectedURL,
        collectionFileClient: collectionFileClient,
        collectionStalenessClient: collectionStalenessClient,
        collectionMetricClient: collectionMetricClient,
        source: "save_new",
    )
}

private func handleSaveCompleted(
    state: inout CollectionState,
    result: Result<CollectionSaveCompletion, Error>,
    userDefaultsClient: UserDefaultsClient,
    collectionStalenessClient: CollectionStalenessClient,
) -> Effect<CollectionAction> {
    resetPendingSave(&state)

    switch result {
    case let .success(completion):
        let url = completion.url
        let file = completion.file
        collectionStalenessClient.upsertRecord(
            url.path,
            .init(
                definitionFingerprint: file.snapshotMeta?.definitionFingerprint ?? "",
                relevanceRoots: file.snapshotMeta?.relevanceRoots ?? file.scopes,
                excludedScopes: file.excludedScopes,
                includeSubfolders: file.includeSubfolders,
                lastInvalidatedAt: nil,
            ),
        )
        let directory = url.deletingLastPathComponent().path
        userDefaultsClient.setString(directory, CollectionKeys.lastCollectionSaveDirectory)
        return .none
    case let .failure(error):
        if state.collectionSession.phase.isInflightWriteBack {
            state.collectionSession.failRefreshOrWriteBack()
        }
        return .send(.delegate(.saveFeedback(.init(
            stage: .saveFailed,
            category: .saveFailed,
            title: "Unable to Save Collection",
            message: error.localizedDescription,
            recoveryHint: "Check the file location or try again.",
            isRetryable: true,
        ))))
    }
}

private func showSaveError(_ failure: CollectionSaveFailure) -> Effect<CollectionAction> {
    .send(.delegate(.saveFeedback(failure.feedback)))
}

// swiftlint:disable:next function_parameter_count
private func performSave(
    snapshot: CollectionSaveSnapshot,
    savedContext: CollectionContext,
    url: URL,
    collectionFileClient: CollectionFileClient,
    collectionStalenessClient: CollectionStalenessClient,
    collectionMetricClient: CollectionMetricClient,
    source: String,
) -> Effect<CollectionAction> {
    let request = buildSaveRequest(
        snapshot: snapshot,
        destinationURL: url,
    )

    collectionStalenessClient.suppressPaths([
        request.url.path,
        request.url.deletingLastPathComponent().path,
    ])

    return executeSave(
        request: request,
        source: source,
        snapshot: snapshot,
        savedContext: savedContext,
        collectionFileClient: collectionFileClient,
        collectionMetricClient: collectionMetricClient,
    )
}
