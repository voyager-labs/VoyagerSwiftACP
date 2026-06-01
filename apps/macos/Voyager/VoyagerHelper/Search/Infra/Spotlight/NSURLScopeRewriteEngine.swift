import Foundation
import VoyagerShared

struct NSURLScopeRewriteEngine: Sendable {
    private struct ScopeRewriteRule {
        let propertyKey: String
        let resolveScopes: (_ value: String, _ volumes: [VolumeInfo]) -> [String]
    }

    struct VolumeInfo: Sendable {
        let rootPath: String
        let name: String?
        let uuidString: String?
        let remountURL: String?
    }

    struct PreparedFilters {
        let scopes: [String]
        let conditions: [SearchConditionPayload]
    }

    func prepare(_ filters: SearchFiltersPayload) -> PreparedFilters {
        prepare(filters, volumeInfos: mountedVolumeInfos())
    }

    func prepare(_ filters: SearchFiltersPayload, volumeInfos: [VolumeInfo]) -> PreparedFilters {
        var scopes = filters.scopes
        var rewrittenConditions: [SearchConditionPayload] = []
        rewrittenConditions.reserveCapacity(filters.conditions.count)
        let rules = scopeRewriteRules()

        for condition in filters.conditions {
            guard let rule = rules[condition.propertyKey] else {
                rewrittenConditions.append(condition)
                continue
            }

            applyScopeRewrite(
                &scopes,
                &rewrittenConditions,
                condition,
                resolver: { value in rule.resolveScopes(value, volumeInfos) },
            )
        }

        return PreparedFilters(scopes: scopes, conditions: rewrittenConditions)
    }
}

private extension NSURLScopeRewriteEngine {
    private func scopeRewriteRules() -> [String: ScopeRewriteRule] {
        let normalizeRule = ScopeRewriteRule(
            propertyKey: "parent_directory_url",
            resolveScopes: { value, _ in
                normalizeScopePath(value).map { [$0] } ?? []
            },
        )
        let volumeURLRule = ScopeRewriteRule(
            propertyKey: "volume_url",
            resolveScopes: { value, _ in
                normalizeScopePath(value).map { [$0] } ?? []
            },
        )
        let volumeNameRule = ScopeRewriteRule(
            propertyKey: "volume_name",
            resolveScopes: { value, volumes in
                volumes.filter { $0.name == value }.map(\.rootPath)
            },
        )
        let volumeUUIDRule = ScopeRewriteRule(
            propertyKey: "volume_uuid_string",
            resolveScopes: { value, volumes in
                volumes.filter { $0.uuidString == value }.map(\.rootPath)
            },
        )
        let remountRule = ScopeRewriteRule(
            propertyKey: "volume_url_for_remounting",
            resolveScopes: { value, volumes in
                volumes.filter { $0.remountURL == value }.map(\.rootPath)
            },
        )

        return [
            normalizeRule.propertyKey: normalizeRule,
            volumeURLRule.propertyKey: volumeURLRule,
            volumeNameRule.propertyKey: volumeNameRule,
            volumeUUIDRule.propertyKey: volumeUUIDRule,
            remountRule.propertyKey: remountRule,
        ]
    }

    func applyScopeRewrite(
        _ scopes: inout [String],
        _ rewrittenConditions: inout [SearchConditionPayload],
        _ condition: SearchConditionPayload,
        resolver: (String) -> [String],
    ) {
        guard condition.operator == "eq", let raw = stringValue(condition.value) else {
            rewrittenConditions.append(condition)
            return
        }

        let roots = resolver(raw)
        if roots.isEmpty {
            rewrittenConditions.append(condition)
        } else {
            scopes.append(contentsOf: roots)
        }
    }

    func mountedVolumeInfos() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeUUIDStringKey, .volumeURLForRemountingKey]
        let volumeURLs = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []

        return volumeURLs.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return VolumeInfo(
                rootPath: normalizeScopePath(url.path) ?? url.standardizedFileURL.path,
                name: values?.volumeName,
                uuidString: values?.volumeUUIDString,
                remountURL: values?.volumeURLForRemounting?.absoluteString,
            )
        }
    }

    func stringValue(_ value: JSONValue?) -> String? {
        guard case let .string(raw)? = value else { return nil }
        return raw
    }

    func normalizeScopePath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let fileURL = URL(string: trimmed), fileURL.isFileURL {
            return SearchScopeNormalizer.normalizeScopes([fileURL.path]).first
        }
        return SearchScopeNormalizer.normalizeScopes([trimmed]).first
    }
}
