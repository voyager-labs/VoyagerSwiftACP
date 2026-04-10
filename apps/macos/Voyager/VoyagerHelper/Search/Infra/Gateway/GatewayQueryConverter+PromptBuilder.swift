import Foundation

extension GatewayQueryConverter {
    func buildSystemPrompt() throws -> String {
        guard let promptURL = resourceBundle.url(
            forResource: "compose_filter_system",
            withExtension: "md",
        ) else {
            throw GatewayQueryError.promptTemplateMissing("compose_filter_system.md")
        }

        let template: String
        do {
            template = try String(contentsOf: promptURL, encoding: .utf8)
        } catch {
            throw GatewayQueryError.promptTemplateLoadFailed(error.localizedDescription)
        }

        guard template.contains("{home_dir}") else {
            throw GatewayQueryError.promptTemplateInvalid("missing {home_dir}")
        }

        return template
            .replacingOccurrences(of: "{home_dir}", with: homeDir)
            .replacingOccurrences(of: "{property_info}", with: "keys from user prompt")
    }

    func buildUserPrompt(
        query: String,
        existingConditions: [SearchConditionPayload],
        existingScopes: [String],
        conditionRegistry: PropertyConditionRegistry,
    ) -> String {
        var parts = ["q=\(query)"]
        let groups = buildKeyGroups(query: query, existingConditions: existingConditions)

        let keysPayload = groups.keys
            .sorted()
            .compactMap { typeName -> String? in
                guard let keys = groups[typeName], keys.isEmpty == false else {
                    return nil
                }
                return "\(typeName):\(keys.sorted().joined(separator: ","))"
            }
            .joined(separator: "|")

        if keysPayload.isEmpty == false {
            parts.append("keys=\(keysPayload)")
        }

        let opsPayload = buildOpsPayload(typeNames: Array(groups.keys), conditionRegistry: conditionRegistry)
        if opsPayload.isEmpty == false {
            parts.append("ops=\(opsPayload)")
        }

        if existingConditions.isEmpty == false,
           let conditionsJSON = encodeJSONString(existingConditions)
        {
            parts.append("conditions=\(conditionsJSON)")
        }

        let queryScopes = inferScopes(from: query)
        if let queryScopes,
           let queryScopesJSON = encodeJSONString(queryScopes)
        {
            parts.append("query_scopes=\(queryScopesJSON)")
        }

        let explicitExistingScopes = existingExplicitScopes(from: existingScopes)
        if explicitExistingScopes.isEmpty == false,
           let existingScopesJSON = encodeJSONString(explicitExistingScopes)
        {
            parts.append("existing_scopes=\(existingScopesJSON)")
        }

        return parts.joined(separator: "\n")
    }

    func encodeJSONString(_ value: some Encodable) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text
    }

    func buildKeyGroups(
        query: String,
        existingConditions: [SearchConditionPayload],
    ) -> [String: [String]] {
        var candidates = GatewayQueryConfig.coreKeys
        for condition in existingConditions {
            candidates.insert(condition.propertyKey)
        }

        let lower = query.lowercased()
        for (key, mapping) in systemPropertyMap {
            if isVisible(mapping) == false {
                continue
            }
            if lower.contains(key.lowercased()) {
                candidates.insert(key)
                continue
            }

            let aliases = mapping.searchAliases ?? []
            if aliases.contains(where: { alias in
                lower.contains(alias.lowercased())
            }) {
                candidates.insert(key)
            }
        }

        var groups: [String: [String]] = [:]
        for key in candidates.sorted() {
            guard let mapping = systemPropertyMap[key], isVisible(mapping) else {
                continue
            }
            groups[mapping.type, default: []].append(key)
        }

        return groups
    }

    func buildOpsPayload(
        typeNames: [String],
        conditionRegistry: PropertyConditionRegistry,
    ) -> String {
        var parts: [String] = []

        for typeName in Set(typeNames).sorted() {
            guard let defaults = conditionRegistry.propertyTypes[typeName] else {
                continue
            }

            let filtered = defaults.operators.filter { operatorCode in
                guard let op = conditionRegistry.operators[operatorCode] else {
                    return false
                }
                if let allowedTypes = op.allowedTypes,
                   allowedTypes.contains(typeName) == false
                {
                    return false
                }
                return true
            }

            parts.append("\(typeName)=\(filtered.joined(separator: ","))")
        }

        return parts.joined(separator: "|")
    }

    func inferScopes(from query: String) -> [String]? {
        let lower = query.lowercased()
        var scopes: [String] = []

        for pattern in GatewayQueryConfig.scopePatterns {
            guard containsWordPattern(pattern.pattern, in: lower) else {
                continue
            }
            let path: String = if pattern.suffix.isEmpty {
                homeDir
            } else {
                URL(fileURLWithPath: homeDir)
                    .appendingPathComponent(pattern.suffix)
                    .path
            }
            if scopes.contains(path) == false {
                scopes.append(path)
            }
        }

        return scopes.isEmpty ? nil : scopes
    }

    func existingExplicitScopes(from scopes: [String]) -> [String] {
        SearchScopeNormalizer.normalizeScopes(scopes).filter { $0 != "/" }
    }

    func containsWordPattern(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    func isVisible(_ definition: SystemPropertyDefinition) -> Bool {
        definition.uiHidden != true
    }

    static func buildSystemPropertyMap(systemRegistry: SystemPropertyRegistry) -> [String: SystemPropertyDefinition] {
        var map: [String: SystemPropertyDefinition] = [:]
        for (_, entries) in systemRegistry.categories {
            for (key, definition) in entries {
                map[key] = definition
            }
        }
        return map
    }
}
