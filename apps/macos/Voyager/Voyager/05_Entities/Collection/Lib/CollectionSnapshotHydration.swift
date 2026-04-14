import CryptoKit
import Foundation
import VoyagerShared

enum CollectionSnapshotHydration {
    static func definitionFingerprint(
        query: String,
        scopes: [String],
        conditions: [CollectionCondition],
    ) -> String {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedScopes = normalizePaths(scopes)
        let normalizedConditions = conditions
            .map { condition in
                let value = canonicalValueString(condition.value)
                return [condition.propertyKey, condition.operatorCode, value].joined(separator: "\u{1E}")
            }
            .sorted()

        return digest(
            query: normalizedQuery,
            scopes: normalizedScopes,
            conditions: normalizedConditions,
        )
    }

    static func definitionFingerprint(file: VoyagerCollectionFile) -> String {
        definitionFingerprint(
            query: file.query,
            scopes: file.scopes,
            conditions: file.conditions,
        )
    }

    static func definitionFingerprint(
        query: String,
        scopes: [String],
        conditions: [Condition],
    ) -> String {
        definitionFingerprint(
            query: query,
            scopes: scopes,
            conditions: collectionConditions(from: conditions),
        )
    }

    static func usableSnapshot(for file: VoyagerCollectionFile) -> CollectionPersistedSnapshot? {
        guard let snapshot = file.snapshot,
              let snapshotMeta = file.snapshotMeta,
              snapshotMeta.definitionFingerprint == definitionFingerprint(file: file)
        else {
            return nil
        }
        return snapshot
    }

    static func syntheticSearchResponse(for file: VoyagerCollectionFile) -> SearchResponsePayload? {
        guard let snapshot = usableSnapshot(for: file) else { return nil }

        return SearchResponsePayload(
            itemCount: file.snapshotMeta?.itemCount ?? snapshot.items.count,
            appliedFilters: .init(
                scopes: file.scopes,
                conditions: file.conditions.map {
                    .init(propertyKey: $0.propertyKey, operator: $0.operatorCode, value: $0.value)
                },
            ),
            items: snapshot.items,
            error: nil,
        )
    }

    private static func normalizePaths(_ paths: [String]) -> [String] {
        paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .sorted()
    }

    private static func collectionConditions(from conditions: [Condition]) -> [CollectionCondition] {
        conditions.compactMap { condition in
            guard condition.isActive,
                  let operatorCode = condition.operatorCode,
                  let arity = condition.operatorValueArity
            else {
                return nil
            }

            if arity == 0 {
                return .init(propertyKey: condition.propertyKey, operatorCode: operatorCode, value: nil)
            }

            guard let values = condition.values,
                  values.count >= arity,
                  let encoded = ConditionValueEncoder.encode(condition: condition, values: values)
            else {
                return nil
            }

            return .init(propertyKey: condition.propertyKey, operatorCode: operatorCode, value: encoded)
        }
    }

    private static func digest(
        query: String,
        scopes: [String],
        conditions: [String],
    ) -> String {
        let canonical = [
            query,
            scopes.joined(separator: "\u{1D}"),
            conditions.joined(separator: "\u{1C}"),
        ].joined(separator: "\u{1B}")

        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalValueString(_ value: JSONValue?) -> String {
        guard let value else { return "null" }

        switch value {
        case let .string(string):
            return "s:\(string)"
        case let .number(number):
            return "n:\(number)"
        case let .bool(boolean):
            return "b:\(boolean)"
        case let .array(values):
            return "a:[\(values.map { canonicalValueString($0) }.joined(separator: ","))]"
        case let .object(values):
            let sorted = values.keys.sorted().map { key in
                "\(key)=\(canonicalValueString(values[key]))"
            }
            return "o:{\(sorted.joined(separator: ","))}"
        case .null:
            return "null"
        }
    }
}
