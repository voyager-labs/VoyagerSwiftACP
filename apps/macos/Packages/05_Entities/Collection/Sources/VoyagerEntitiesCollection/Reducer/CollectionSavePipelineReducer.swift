import AppKit
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

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .saveRequested(payload):
                handleSaveRequested(
                    state: &state,
                    payload: payload,
                    collectionSavePanelClient: collectionSavePanelClient,
                )

            case let .saveToExisting(payload, url):
                handleSaveToExisting(
                    state: &state,
                    payload: payload,
                    url: url,
                    collectionFileClient: collectionFileClient,
                    collectionStalenessClient: collectionStalenessClient,
                )

            case let .savePanelResponse(url):
                handleSavePanelResponse(
                    state: &state,
                    selectedURL: url,
                    collectionFileClient: collectionFileClient,
                    collectionStalenessClient: collectionStalenessClient,
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

private enum CollectionSaveValidationError: LocalizedError {
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
    let title: String
    let message: String
}

private func validateSavePayload(
    _ payload: SaveRequestPayload,
) -> Result<(snapshot: CollectionSaveSnapshot, context: CollectionContext), CollectionSaveFailure> {
    guard let context = payload.context else {
        return .failure(.init(
            title: "No New Collection",
            message: "There is no active new collection to save.",
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
            title: "Unable to Save Collection",
            message: error.localizedDescription,
        ))
    case let .success(snapshot):
        return .success((snapshot: snapshot, context: context))
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
) -> Effect<CollectionAction> {
    guard canStartSave(state: state, payload: payload) else { return .none }

    switch validateSavePayload(payload) {
    case let .failure(failure):
        return showSaveError(failure)
    case let .success(result):
        state.pendingSave = result.snapshot
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
) -> Effect<CollectionAction> {
    guard canStartSave(state: state, payload: payload) else { return .none }

    switch validateSavePayload(payload) {
    case let .failure(failure):
        return showSaveError(failure)
    case let .success(result):
        state.isSaving = true
        return performSave(
            snapshot: result.snapshot,
            url: url,
            collectionFileClient: collectionFileClient,
            collectionStalenessClient: collectionStalenessClient,
        )
    }
}

private func handleSavePanelResponse(
    state: inout CollectionState,
    selectedURL: URL?,
    collectionFileClient: CollectionFileClient,
    collectionStalenessClient: CollectionStalenessClient,
) -> Effect<CollectionAction> {
    guard let selectedURL, let snapshot = state.pendingSave else {
        resetPendingSave(&state)
        return .none
    }

    return performSave(
        snapshot: snapshot,
        url: selectedURL,
        collectionFileClient: collectionFileClient,
        collectionStalenessClient: collectionStalenessClient,
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
        return showSaveError(.init(
            title: "Unable to Save Collection",
            message: error.localizedDescription,
        ))
    }
}

private func makeCollectionFile(
    name: String,
    snapshot: CollectionSaveSnapshot,
    appVersion: String?,
) -> VoyagerCollectionFile {
    let timestamp = Date()
    return VoyagerCollectionFile(
        id: UUID().uuidString,
        name: name,
        createdAt: timestamp,
        updatedAt: timestamp,
        query: snapshot.query,
        scopes: snapshot.scopes,
        excludedScopes: snapshot.excludedScopes,
        includeSubfolders: snapshot.includeSubfolders,
        includeDirectories: snapshot.includeDirectories,
        conditions: snapshot.conditions,
        snapshot: snapshot.snapshotItems.map(CollectionPersistedSnapshot.init(items:)),
        snapshotMeta: snapshot.snapshotItems.map { snapshotItems in
            .init(
                definitionFingerprint: snapshot.definitionFingerprint,
                capturedAt: snapshot.capturedAt,
                itemCount: snapshotItems.count,
                relevanceRoots: snapshot.relevanceRoots,
            )
        },
        appVersion: appVersion,
    )
}

private func currentAppVersion() -> String? {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String
    let build = info?["CFBundleVersion"] as? String

    switch (version, build) {
    case let (.some(version), .some(build)):
        return "\(version) (\(build))"
    case let (.some(version), .none):
        return version
    case let (.none, .some(build)):
        return build
    default:
        return nil
    }
}

@MainActor
private func showCollectionSaveErrorAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

private func showSaveError(_ failure: CollectionSaveFailure) -> Effect<CollectionAction> {
    .run { _ in
        await showCollectionSaveErrorAlert(
            title: failure.title,
            message: failure.message,
        )
    }
}

private func performSave(
    snapshot: CollectionSaveSnapshot,
    url: URL,
    collectionFileClient: CollectionFileClient,
    collectionStalenessClient: CollectionStalenessClient,
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
        collectionFileClient: collectionFileClient,
    )
}

private struct CollectionSaveRequest {
    let url: URL
    let file: VoyagerCollectionFile
}

private func buildSaveRequest(
    snapshot: CollectionSaveSnapshot,
    destinationURL: URL,
) -> CollectionSaveRequest {
    let finalURL: URL = if destinationURL.pathExtension.lowercased() == CollectionConstants.fileExtension {
        destinationURL
    } else {
        destinationURL
            .deletingPathExtension()
            .appendingPathExtension(CollectionConstants.fileExtension)
    }
    let file = makeCollectionFile(
        name: finalURL.deletingPathExtension().lastPathComponent,
        snapshot: snapshot,
        appVersion: currentAppVersion(),
    )
    return .init(url: finalURL, file: file)
}

private func executeSave(
    request: CollectionSaveRequest,
    collectionFileClient: CollectionFileClient,
) -> Effect<CollectionAction> {
    .run { send in
        do {
            try await collectionFileClient.save(request.file, request.url)
            await send(.saveCompleted(.success(.init(url: request.url, file: request.file))))
        } catch {
            await send(.saveCompleted(.failure(error)))
        }
    }
}
