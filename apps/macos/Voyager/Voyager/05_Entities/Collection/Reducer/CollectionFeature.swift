import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@Reducer
struct CollectionFeature {
    typealias State = CollectionState
    typealias Action = CollectionAction

    @Dependency(\.collectionFileClient)
    var collectionFileClient

    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .saveRequested(payload):
                handleSaveRequested(
                    state: &state,
                    payload: payload,
                    userDefaultsClient: userDefaultsClient,
                )

            case let .saveToExisting(payload, url):
                handleSaveToExisting(
                    state: &state,
                    payload: payload,
                    url: url,
                    collectionFileClient: collectionFileClient,
                )

            case let .savePanelResponse(url):
                handleSavePanelResponse(
                    state: &state,
                    selectedURL: url,
                    collectionFileClient: collectionFileClient,
                )

            case let .saveCompleted(result):
                handleSaveCompleted(
                    state: &state,
                    result: result,
                    userDefaultsClient: userDefaultsClient,
                )
            }
        }
    }
}

private let kCollectionSchemaVersion: Int = 1

private enum CollectionSaveValidationError: LocalizedError {
    case emptyContent
    case incompleteCondition(String)
    case invalidConditionValue(String)

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
) -> Result<CollectionSaveSnapshot, CollectionSaveValidationError> {
    if query.isEmpty, context.scopes.isEmpty, context.conditions.isEmpty {
        return .failure(.emptyContent)
    }

    do {
        let conditions = try buildCollectionConditions(from: context.conditions)
        return .success(.init(
            query: query,
            scopes: context.scopes,
            conditions: conditions,
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

private func resetPendingSave(_ state: inout CollectionFeature.State) {
    state.isSaving = false
    state.pendingSave = nil
}

private func handleSaveRequested(
    state: inout CollectionFeature.State,
    payload: SaveRequestPayload,
    userDefaultsClient: UserDefaultsClient,
) -> Effect<CollectionFeature.Action> {
    guard !state.isSaving else { return .none }
    guard !payload.isSearchLoading, !payload.isFiltersLoading else { return .none }

    switch validateSavePayload(payload) {
    case let .failure(failure):
        return showSaveError(failure)
    case let .success(result):
        state.pendingSave = result.snapshot
        state.isSaving = true
        return .run { send in
            let initialDirectory = await defaultCollectionSaveDirectory(
                preferredScopes: result.context.scopes,
                userDefaultsClient: userDefaultsClient,
            )
            let url = await showCollectionSavePanel(initialDirectory: initialDirectory)
            await send(.savePanelResponse(url))
        }
    }
}

private func handleSaveToExisting(
    state: inout CollectionFeature.State,
    payload: SaveRequestPayload,
    url: URL,
    collectionFileClient: CollectionFileClient,
) -> Effect<CollectionFeature.Action> {
    guard !state.isSaving else { return .none }
    guard !payload.isSearchLoading, !payload.isFiltersLoading else { return .none }

    switch validateSavePayload(payload) {
    case let .failure(failure):
        return showSaveError(failure)
    case let .success(result):
        state.isSaving = true
        return performSave(
            snapshot: result.snapshot,
            url: url,
            collectionFileClient: collectionFileClient,
        )
    }
}

private func handleSavePanelResponse(
    state: inout CollectionFeature.State,
    selectedURL: URL?,
    collectionFileClient: CollectionFileClient,
) -> Effect<CollectionFeature.Action> {
    guard let selectedURL, let snapshot = state.pendingSave else {
        resetPendingSave(&state)
        return .none
    }

    return performSave(
        snapshot: snapshot,
        url: selectedURL,
        collectionFileClient: collectionFileClient,
    )
}

private func handleSaveCompleted(
    state: inout CollectionFeature.State,
    result: Result<URL, Error>,
    userDefaultsClient: UserDefaultsClient,
) -> Effect<CollectionFeature.Action> {
    resetPendingSave(&state)

    switch result {
    case let .success(url):
        let directory = url.deletingLastPathComponent().path
        userDefaultsClient.setString(directory, CollectionKeys.lastCollectionSaveDirectory)
        return .none
    case let .failure(error):
        return showSaveError(.init(
            title: "Unable to Save Collection",
            message: error.localizedDescription,
        ))
    }
}

@MainActor
private func defaultCollectionSaveDirectory(
    preferredScopes: [String],
    userDefaultsClient: UserDefaultsClient,
) -> URL? {
    let fileManager = FileManager.default
    if preferredScopes.count == 1,
       let scope = preferredScopes.first,
       let url = validDirectoryURL(scope, fileManager: fileManager)
    {
        return url
    }

    if let saved = userDefaultsClient.string(CollectionKeys.lastCollectionSaveDirectory),
       let url = validDirectoryURL(saved, fileManager: fileManager)
    {
        return url
    }

    return URL(fileURLWithPath: NSHomeDirectory())
}

private func validDirectoryURL(_ path: String, fileManager: FileManager) -> URL? {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return nil
    }
    return URL(fileURLWithPath: path)
}

@MainActor
private func showCollectionSavePanel(initialDirectory: URL?) -> URL? {
    let panel = NSSavePanel()
    panel.title = "Save Collection"
    panel.prompt = "Save"
    panel.canCreateDirectories = true
    panel.allowsOtherFileTypes = false
    panel.allowedContentTypes = [
        UTType("fm.voyager.collection")
            ?? UTType(filenameExtension: CollectionConstants.fileExtension)
            ?? .data,
    ]
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = ""
    panel.directoryURL = initialDirectory

    let response = panel.runModal()
    guard response == .OK else { return nil }
    return panel.url
}

private func ensureCollectionFileExtension(_ url: URL) -> URL {
    if url.pathExtension.lowercased() == CollectionConstants.fileExtension {
        return url
    }
    return url.deletingPathExtension().appendingPathExtension(CollectionConstants.fileExtension)
}

private func makeCollectionFile(
    name: String,
    snapshot: CollectionSaveSnapshot,
    appVersion: String?,
) -> VoyagerCollectionFile {
    let timestamp = Date()
    return VoyagerCollectionFile(
        schemaVersion: kCollectionSchemaVersion,
        id: UUID().uuidString,
        name: name,
        createdAt: timestamp,
        updatedAt: timestamp,
        query: snapshot.query,
        scopes: snapshot.scopes,
        conditions: snapshot.conditions,
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

private func showSaveError(_ failure: CollectionSaveFailure) -> Effect<CollectionFeature.Action> {
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
) -> Effect<CollectionFeature.Action> {
    let request = buildSaveRequest(
        snapshot: snapshot,
        destinationURL: url,
    )

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
    let finalURL = ensureCollectionFileExtension(destinationURL)
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
) -> Effect<CollectionFeature.Action> {
    .run { send in
        do {
            try await collectionFileClient.save(request.file, request.url)
            await send(.saveCompleted(.success(request.url)))
        } catch {
            await send(.saveCompleted(.failure(error)))
        }
    }
}
