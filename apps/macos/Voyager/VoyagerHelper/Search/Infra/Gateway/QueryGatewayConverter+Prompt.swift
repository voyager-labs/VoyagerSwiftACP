import Foundation

extension QueryGatewayConverter {
    func buildSystemPrompt() -> String {
        QueryGatewaySystemPrompt.template
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

        if existingScopes.isEmpty == false,
           let scopesJSON = encodeJSONString(existingScopes)
        {
            parts.append("scopes=\(scopesJSON)")
        } else if let inferredScopes = inferScopes(from: query),
                  let scopesJSON = encodeJSONString(inferredScopes)
        {
            parts.append("scopes=\(scopesJSON)")
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
        var candidates = QueryGatewayConverterConfig.coreKeys
        for condition in existingConditions {
            candidates.insert(condition.propertyKey)
        }

        let lower = query.lowercased()
        for (key, mapping) in propertyMap {
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
            guard let mapping = propertyMap[key], isVisible(mapping) else {
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

        for pattern in QueryGatewayConverterConfig.scopePatterns {
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

    func containsWordPattern(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    func normalizeAndValidateConditions(
        _ conditions: [SearchConditionPayload],
        conditionRegistry: PropertyConditionRegistry,
    ) -> [SearchConditionPayload] {
        var result: [SearchConditionPayload] = []

        for condition in conditions {
            guard let normalized = normalizeCondition(condition) else {
                continue
            }
            guard isValidCondition(normalized, conditionRegistry: conditionRegistry) else {
                continue
            }
            result.append(normalized)
        }

        return result
    }

    func normalizeCondition(_ condition: SearchConditionPayload) -> SearchConditionPayload? {
        if condition.operator == "eq", condition.value == nil {
            return nil
        }

        if condition.operator == "rx", case let .string(text)? = condition.value {
            let normalized: String = if text.contains("%") {
                text
            } else if text.contains(".*") {
                text.replacingOccurrences(of: ".*", with: "%")
            } else {
                text
            }

            return SearchConditionPayload(
                propertyKey: condition.propertyKey,
                operator: condition.operator,
                value: .string(normalized),
            )
        }

        return condition
    }

    func isValidCondition(
        _ condition: SearchConditionPayload,
        conditionRegistry: PropertyConditionRegistry,
    ) -> Bool {
        guard let mapping = propertyMap[condition.propertyKey], isVisible(mapping) else {
            return false
        }
        guard let typeKey = conditionTypeKey(for: mapping.type),
              let propertyType = conditionRegistry.propertyTypes[typeKey]
        else {
            return false
        }
        guard propertyType.operators.contains(condition.operator) else {
            return false
        }
        guard let operatorMeta = conditionRegistry.operators[condition.operator] else {
            return false
        }
        return isValidValueCount(operatorMeta.valueCount, value: condition.value)
    }

    func conditionTypeKey(for rawType: String) -> String? {
        switch rawType.lowercased() {
        case "string":
            "string"
        case "categorical":
            "categorical"
        case "number":
            "number"
        case "date", "datetime":
            "date"
        case "boolean":
            "boolean"
        case "string_list":
            "string_list"
        default:
            nil
        }
    }

    func isValidValueCount(_ valueCount: ValueCount?, value: JSONValue?) -> Bool {
        guard let valueCount else {
            return true
        }

        switch valueCount {
        case .fixed(0):
            return value == nil
        case .fixed(1):
            return value != nil
        case .fixed(2):
            if case let .array(values)? = value {
                return values.count == 2
            }
            return false
        case .multiple:
            if case let .array(values)? = value {
                return values.isEmpty == false
            }
            return false
        default:
            return true
        }
    }

    func isVisible(_ definition: SystemPropertyDefinition) -> Bool {
        definition.uiHidden != true
    }

    func isVisibleKey(_ key: String) -> Bool {
        guard let definition = propertyMap[key] else {
            return false
        }
        return isVisible(definition)
    }

    static func buildPropertyMap(systemRegistry: SystemPropertyRegistry) -> [String: SystemPropertyDefinition] {
        var map: [String: SystemPropertyDefinition] = [:]
        for (_, entries) in systemRegistry.categories {
            for (key, definition) in entries {
                map[key] = definition
            }
        }
        return map
    }
}
