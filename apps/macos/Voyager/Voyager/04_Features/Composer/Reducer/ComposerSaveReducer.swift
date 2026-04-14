import ComposableArchitecture
import Foundation
import VoyagerShared

@Reducer
struct ComposerSaveReducer {
    typealias State = ComposerState
    typealias Action = ComposerAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.saveCollection):
                let payload = makeSavePayload(from: state)
                if let url = state.openedCollectionURL {
                    return .send(.collection(.saveToExisting(payload, url)))
                }
                return .send(.collection(.saveRequested(payload)))

            case .view(.saveCollectionAs):
                return .send(.collection(.saveRequested(makeSavePayload(from: state))))

            case .collection:
                return .none

            default:
                return .none
            }
        }
    }
}

private func makeSavePayload(from state: ComposerState) -> SaveRequestPayload {
    let context = state.collectionContext
    let query = context?.query.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let scopes = context?.scopes ?? []
    let conditions = context?.conditions ?? []
    return .init(
        context: context,
        isSearchLoading: state.isLoadingSearch,
        isFiltersLoading: state.isLoadingFilters,
        snapshotItems: makeSnapshotItems(from: state.lastFiltersResponse?.items),
        definitionFingerprint: makeDefinitionFingerprint(
            query: query,
            scopes: scopes,
            conditions: conditions,
        ),
        capturedAt: Date(),
        relevanceRoots: scopes.map(standardizedPath).sorted(),
    )
}

private func makeSnapshotItems(from items: [JSONValue]?) -> [JSONValue]? {
    guard let items else { return nil }
    let pathItems = items.compactMap { item -> JSONValue? in
        guard case let .object(values) = item,
              case let .string(fullPath) = values["fullPath"]
        else {
            return nil
        }
        return .string(standardizedPath(fullPath))
    }
    return pathItems.isEmpty ? nil : pathItems
}

private func makeDefinitionFingerprint(
    query: String,
    scopes: [String],
    conditions: [Condition],
) -> String {
    struct FingerprintPayload: Encodable {
        struct ConditionPayload: Encodable {
            let propertyKey: String
            let propertyLabel: String
            let operatorCode: String?
            let operatorValueArity: Int?
            let values: [String]?
            let isActive: Bool
        }

        let query: String
        let scopes: [String]
        let conditions: [ConditionPayload]
    }

    let payload = FingerprintPayload(
        query: query,
        scopes: scopes.map(standardizedPath).sorted(),
        conditions: conditions.map {
            FingerprintPayload.ConditionPayload(
                propertyKey: $0.propertyKey,
                propertyLabel: $0.propertyLabel,
                operatorCode: $0.operatorCode,
                operatorValueArity: $0.operatorValueArity,
                values: $0.values,
                isActive: $0.isActive,
            )
        },
    )

    let encoder = JSONEncoder()
    if #available(macOS 13.0, *) {
        encoder.outputFormatting = [.sortedKeys]
    }

    let data = try? encoder.encode(payload)
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
}

private func standardizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
