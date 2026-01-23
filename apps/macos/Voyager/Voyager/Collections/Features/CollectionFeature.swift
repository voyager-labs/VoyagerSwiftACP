import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@Reducer
struct CollectionFeature {
    @ObservableState
    struct State: Equatable {
        var pendingSave: CollectionSaveSnapshot?
        var isSaving: Bool = false
    }

    struct CollectionSaveSnapshot: Equatable, Sendable {
        let query: String
        let scopes: [String]
        let conditions: [CollectionCondition]
        let sortKey: String
        let sortOrder: String
        let viewLayout: String
    }

    struct SaveRequestPayload: Equatable, Sendable {
        let context: CollectionContext?
        let sortKey: String
        let sortOrder: String
        let viewLayout: String
        let isSearchLoading: Bool
        let isFiltersLoading: Bool
    }

    enum Action: Sendable {
        case saveRequested(SaveRequestPayload)
        case saveToExisting(SaveRequestPayload, URL)
        case savePanelResponse(URL?)
        case saveCompleted(Result<URL, Error>)
    }

    @Dependency(\.collectionFileClient)
    var collectionFileClient

    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    @Dependency(\.entryClient)
    var entryClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .saveRequested(payload):
                guard !state.isSaving else { return .none }
                guard !payload.isSearchLoading, !payload.isFiltersLoading else { return .none }
                guard let context = payload.context else {
                    return .run { _ in
                        await showCollectionSaveErrorAlert(
                            title: "No New Collection",
                            message: "There is no active new collection to save.",
                        )
                    }
                }

                let trimmedQuery = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
                let validation = validateCollectionContext(
                    context,
                    query: trimmedQuery,
                    sortKey: payload.sortKey,
                    sortOrder: payload.sortOrder,
                    viewLayout: payload.viewLayout,
                )

                switch validation {
                case let .failure(error):
                    return .run { _ in
                        await showCollectionSaveErrorAlert(
                            title: "Unable to Save Collection",
                            message: error.localizedDescription,
                        )
                    }

                case let .success(snapshot):
                    state.pendingSave = snapshot
                    state.isSaving = true
                    return .run { [userDefaultsClient] send in
                        let initialDirectory = await defaultCollectionSaveDirectory(
                            preferredScopes: context.scopes,
                            userDefaultsClient: userDefaultsClient,
                            entryClient: entryClient,
                        )
                        let url = await showCollectionSavePanel(initialDirectory: initialDirectory)
                        await send(.savePanelResponse(url))
                    }
                }

            case let .saveToExisting(payload, url):
                guard !state.isSaving else { return .none }
                guard !payload.isSearchLoading, !payload.isFiltersLoading else { return .none }
                guard let context = payload.context else {
                    return .run { _ in
                        await showCollectionSaveErrorAlert(
                            title: "No New Collection",
                            message: "There is no active new collection to save.",
                        )
                    }
                }

                let trimmedQuery = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
                let validation = validateCollectionContext(
                    context,
                    query: trimmedQuery,
                    sortKey: payload.sortKey,
                    sortOrder: payload.sortOrder,
                    viewLayout: payload.viewLayout,
                )

                switch validation {
                case let .failure(error):
                    return .run { _ in
                        await showCollectionSaveErrorAlert(
                            title: "Unable to Save Collection",
                            message: error.localizedDescription,
                        )
                    }

                case let .success(snapshot):
                    state.isSaving = true
                    let finalURL = ensureCollectionFileExtension(url)
                    let file = makeCollectionFile(
                        name: finalURL.deletingPathExtension().lastPathComponent,
                        snapshot: snapshot,
                        appVersion: currentAppVersion(),
                    )

                    return .run { send in
                        do {
                            try await collectionFileClient.save(file, finalURL)
                            await send(.saveCompleted(.success(finalURL)))
                        } catch {
                            await send(.saveCompleted(.failure(error)))
                        }
                    }
                }

            case let .savePanelResponse(url):
                guard let url else {
                    resetPendingSave(&state)
                    return .none
                }

                guard let snapshot = state.pendingSave else {
                    resetPendingSave(&state)
                    return .none
                }

                let finalURL = ensureCollectionFileExtension(url)
                let file = makeCollectionFile(
                    name: finalURL.deletingPathExtension().lastPathComponent,
                    snapshot: snapshot,
                    appVersion: currentAppVersion(),
                )

                return .run { send in
                    do {
                        try await collectionFileClient.save(file, finalURL)
                        await send(.saveCompleted(.success(finalURL)))
                    } catch {
                        await send(.saveCompleted(.failure(error)))
                    }
                }

            case let .saveCompleted(result):
                resetPendingSave(&state)

                switch result {
                case let .success(url):
                    let directory = url.deletingLastPathComponent().path
                    userDefaultsClient.setString(directory, SettingsKeys.lastCollectionSaveDirectory)
                    return .none

                case let .failure(error):
                    return .run { _ in
                        await showCollectionSaveErrorAlert(
                            title: "Unable to Save Collection",
                            message: error.localizedDescription,
                        )
                    }
                }
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

private func validateCollectionContext(
    _ context: CollectionContext,
    query: String,
    sortKey: String,
    sortOrder: String,
    viewLayout: String,
) -> Result<CollectionFeature.CollectionSaveSnapshot, CollectionSaveValidationError> {
    if query.isEmpty, context.scopes.isEmpty, context.conditions.isEmpty {
        return .failure(.emptyContent)
    }

    do {
        let conditions = try buildCollectionConditions(from: context.conditions)
        return .success(.init(
            query: query,
            scopes: context.scopes,
            conditions: conditions,
            sortKey: sortKey,
            sortOrder: sortOrder,
            viewLayout: viewLayout,
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

        guard let encoded = encodeCollectionValue(condition: condition, values: values) else {
            throw CollectionSaveValidationError.invalidConditionValue(condition.propertyLabel)
        }

        results.append(.init(propertyKey: condition.propertyKey, operatorCode: op, value: encoded))
    }

    return results
}

private func encodeCollectionValue(condition: Condition, values: [String]) -> JSONValue? {
    if let kind = condition.operatorValueUIKind {
        switch kind {
        case "listText":
            return .array(values.map(JSONValue.string))
        case "listNumber":
            let numbers = values.compactMap(Double.init)
            guard numbers.count == values.count else { return nil }
            return .array(numbers.map(JSONValue.number))
        default:
            break
        }
    }
    return switch condition.valueType {
    case "number":
        encodeNumberValues(values)

    case "boolean":
        encodeBooleanValues(values)

    case "date", "datetime":
        encodeDateValues(values)

    case "string_list", "string", "unknown":
        encodeStringValues(values, operatorCode: condition.operatorCode)

    default:
        encodeStringValues(values, operatorCode: condition.operatorCode)
    }
}

private func encodeNumberValues(_ values: [String]) -> JSONValue? {
    let numbers = values.compactMap(Double.init)
    guard numbers.count == values.count else { return nil }
    if numbers.count == 1, let first = numbers.first {
        return .number(first)
    }
    return .array(numbers.map(JSONValue.number))
}

private func encodeBooleanValues(_ values: [String]) -> JSONValue? {
    guard let first = values.first?.lowercased() else { return nil }
    if first == "true" {
        return .bool(true)
    }
    if first == "false" {
        return .bool(false)
    }
    return nil
}

private func encodeDateValues(_ values: [String]) -> JSONValue? {
    let formattedValues = values.map { value in
        ValueNormalizerUtils.formatDateOnlyString(value) ?? value
    }
    if formattedValues.count == 1 {
        return .string(formattedValues[0])
    }
    return .array(formattedValues.map(JSONValue.string))
}

private func encodeStringValues(_ values: [String], operatorCode: String?) -> JSONValue? {
    let op = operatorCode?.lowercased()
    if op == "in" || op == "anyof" {
        return .array(values.map(JSONValue.string))
    }
    if values.count == 1 {
        return .string(values[0])
    }
    return .array(values.map(JSONValue.string))
}

private func resetPendingSave(_ state: inout CollectionFeature.State) {
    state.isSaving = false
    state.pendingSave = nil
}

@MainActor
private func defaultCollectionSaveDirectory(
    preferredScopes: [String],
    userDefaultsClient: UserDefaultsClient,
    entryClient: EntryClient,
) -> URL? {
    if preferredScopes.count == 1,
       let scope = preferredScopes.first,
       let url = validDirectoryURL(scope, entryClient: entryClient)
    {
        return url
    }

    if let saved = userDefaultsClient.string(SettingsKeys.lastCollectionSaveDirectory),
       let url = validDirectoryURL(saved, entryClient: entryClient)
    {
        return url
    }

    return URL(fileURLWithPath: entryClient.homeDirectory())
}

private func validDirectoryURL(_ path: String, entryClient: EntryClient) -> URL? {
    var isDirectory: ObjCBool = false
    guard entryClient.fileExistsAtPath(path, &isDirectory), isDirectory.boolValue else {
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
            ?? UTType(filenameExtension: "voycoll")
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
    if url.pathExtension.lowercased() == "voycoll" {
        return url
    }
    return url.deletingPathExtension().appendingPathExtension("voycoll")
}

private func makeCollectionFile(
    name: String,
    snapshot: CollectionFeature.CollectionSaveSnapshot,
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
        sortKey: snapshot.sortKey,
        sortOrder: snapshot.sortOrder,
        viewLayout: snapshot.viewLayout,
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
