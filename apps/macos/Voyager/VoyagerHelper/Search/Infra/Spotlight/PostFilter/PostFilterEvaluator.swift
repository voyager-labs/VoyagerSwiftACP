@preconcurrency import CoreServices
import Foundation
import UniformTypeIdentifiers

struct PostFilterEvaluator: Sendable {
    enum EvaluationError: Error, LocalizedError {
        case unknownPropertyKey(String)
        case unsupportedPropertyType(String)
        case unsupportedOperator(propertyKey: String, operatorCode: String)
        case invalidValue(propertyKey: String, operatorCode: String)

        var errorDescription: String? {
            switch self {
            case let .unknownPropertyKey(propertyKey):
                "Unknown property key: \(propertyKey)"
            case let .unsupportedPropertyType(type):
                "Unsupported property type: \(type)"
            case let .unsupportedOperator(propertyKey, operatorCode):
                "Operator '\(operatorCode)' is not supported for '\(propertyKey)'"
            case let .invalidValue(propertyKey, operatorCode):
                "Invalid value for '\(propertyKey)' with operator '\(operatorCode)'"
            }
        }
    }

    private let conditionBuilder: SearchConditionBuilder

    init(bundle: Bundle = .main) throws {
        try self.init(conditionBuilder: SearchConditionBuilder(bundle: bundle))
    }

    init(
        conditionBuilder: SearchConditionBuilder,
    ) {
        self.conditionBuilder = conditionBuilder
    }

    func filter(paths: [String], conditions: [SearchConditionPayload]) throws -> [String] {
        guard conditions.isEmpty == false else {
            return paths
        }

        let specs = try conditions.map(prepareSpec).sorted(by: shouldEvaluateFirst)
        let nsurlSymbols = batchedNSURLSymbols(from: specs)

        if shouldEvaluateInParallel(pathCount: paths.count) {
            return try filterPathsInParallel(paths: paths, specs: specs, nsurlSymbols: nsurlSymbols)
        }

        return try filterPathsSequentially(paths: paths, specs: specs, nsurlSymbols: nsurlSymbols)
    }
}

extension PostFilterEvaluator {
    struct ConditionSpec: Sendable {
        let condition: SearchConditionPayload
        let mapping: SearchConditionBuilder.PropertyMapping
        let typeKey: String
        let orderedSystemKeys: [SystemKey]
        let evaluationPriority: Int
    }

    struct SystemKey: Sendable {
        let prefix: String
        let symbol: String
    }

    enum CachedValue {
        case missing
        case value(Any)
    }

    struct PathContext {
        let path: String
        let url: URL
        var mdItem: MDItem?
        var propertyCache: [String: CachedValue]
        var resourceCache: [String: CachedValue]
        var mdItemAttributeCache: [String: CachedValue]

        init(path: String) {
            self.path = path
            url = URL(fileURLWithPath: path)
            mdItem = nil
            propertyCache = [:]
            resourceCache = [:]
            mdItemAttributeCache = [:]
        }

        mutating func loadMDItem() -> MDItem? {
            if let mdItem {
                return mdItem
            }
            guard let created = MDItemCreate(kCFAllocatorDefault, path as CFString) else {
                return nil
            }
            mdItem = created
            return created
        }
    }

    func prepareSpec(_ condition: SearchConditionPayload) throws -> ConditionSpec {
        guard let mapping = conditionBuilder.propertyMap[condition.propertyKey] else {
            throw EvaluationError.unknownPropertyKey(condition.propertyKey)
        }

        guard let typeKey = conditionBuilder.conditionTypeKey(for: mapping.type),
              let propertyType = conditionBuilder.registry.propertyTypes[typeKey]
        else {
            throw EvaluationError.unsupportedPropertyType(mapping.type)
        }

        guard propertyType.operators.contains(condition.operator),
              let operatorMeta = conditionBuilder.registry.operators[condition.operator]
        else {
            throw EvaluationError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        if let allowedTypes = operatorMeta.allowedTypes,
           allowedTypes.contains(typeKey) == false
        {
            throw EvaluationError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        do {
            try conditionBuilder.validateValue(
                operatorMeta.valueCount,
                operatorCode: condition.operator,
                value: condition.value,
                propertyKey: condition.propertyKey,
            )
        } catch {
            throw EvaluationError.invalidValue(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        let orderedSystemKeys = orderedSystemKeys(from: mapping.systemKeys)
        return ConditionSpec(
            condition: condition,
            mapping: mapping,
            typeKey: typeKey,
            orderedSystemKeys: orderedSystemKeys,
            evaluationPriority: evaluationPriority(
                typeKey: typeKey,
                operatorCode: condition.operator,
                orderedSystemKeys: orderedSystemKeys,
            ),
        )
    }

    func matchesAll(specs: [ConditionSpec], context: inout PathContext) throws -> Bool {
        for spec in specs where try evaluate(spec: spec, context: &context) == false {
            return false
        }
        return true
    }

    func evaluate(spec: ConditionSpec, context: inout PathContext) throws -> Bool {
        let operatorCode = spec.condition.operator
        let rawValue = resolvePropertyValue(spec: spec, context: &context)

        if operatorCode == "exists" {
            return isPresent(rawValue, typeKey: spec.typeKey)
        }
        if operatorCode == "empty" {
            return isEmpty(rawValue, typeKey: spec.typeKey)
        }

        switch spec.typeKey {
        case "string":
            return try evaluateString(spec: spec, rawValue: rawValue)
        case "categorical":
            return try evaluateCategorical(spec: spec, rawValue: rawValue)
        case "string_list":
            return try evaluateStringList(spec: spec, rawValue: rawValue)
        case "number":
            return try evaluateNumber(spec: spec, rawValue: rawValue)
        case "date":
            return try evaluateDate(spec: spec, rawValue: rawValue)
        case "boolean":
            return try evaluateBoolean(spec: spec, rawValue: rawValue)
        default:
            throw EvaluationError.unsupportedPropertyType(spec.mapping.type)
        }
    }

    func evaluateString(spec: ConditionSpec, rawValue: Any?) throws -> Bool {
        let lhs = normalizedString(rawValue) ?? ""
        let rhs = try readString(spec.condition)

        switch spec.condition.operator {
        case "eq":
            return equals(lhs, rhs)
        case "neq":
            return !equals(lhs, rhs)
        case "cn":
            return contains(lhs, rhs)
        case "nc":
            return !contains(lhs, rhs)
        case "sw":
            return lhs.lowercased().hasPrefix(rhs.lowercased())
        case "ew":
            return lhs.lowercased().hasSuffix(rhs.lowercased())
        case "rx":
            return wildcardMatch(lhs, pattern: rhs)
        default:
            throw EvaluationError.unsupportedOperator(
                propertyKey: spec.condition.propertyKey,
                operatorCode: spec.condition.operator,
            )
        }
    }

    func evaluateCategorical(spec: ConditionSpec, rawValue: Any?) throws -> Bool {
        switch spec.condition.operator {
        case "any", "none", "all", "miss":
            let lhs = normalizedStringList(rawValue)
            let rhs = try readStringList(spec.condition)
            let matchAny = containsAny(lhs, rhs)
            let matchAll = containsAll(lhs, rhs)

            switch spec.condition.operator {
            case "any": return matchAny
            case "none": return !matchAny
            case "all": return matchAll
            case "miss": return !matchAll
            default: return false
            }
        default:
            return try evaluateString(spec: spec, rawValue: rawValue)
        }
    }

    func evaluateStringList(spec: ConditionSpec, rawValue: Any?) throws -> Bool {
        let lhs = normalizedStringList(rawValue)

        switch spec.condition.operator {
        case "any", "none", "all", "miss":
            let rhs = try readStringList(spec.condition)
            let matchAny = containsAny(lhs, rhs)
            let matchAll = containsAll(lhs, rhs)

            switch spec.condition.operator {
            case "any": return matchAny
            case "none": return !matchAny
            case "all": return matchAll
            case "miss": return !matchAll
            default: return false
            }
        default:
            throw EvaluationError.unsupportedOperator(
                propertyKey: spec.condition.propertyKey,
                operatorCode: spec.condition.operator,
            )
        }
    }

    func evaluateNumber(spec: ConditionSpec, rawValue: Any?) throws -> Bool {
        guard let lhs = normalizedNumber(rawValue) else {
            return false
        }

        switch spec.condition.operator {
        case "eq":
            return try lhs == readNumber(spec.condition)
        case "neq":
            return try lhs != readNumber(spec.condition)
        case "gt":
            return try lhs > readNumber(spec.condition)
        case "gte":
            return try lhs >= readNumber(spec.condition)
        case "lt":
            return try lhs < readNumber(spec.condition)
        case "lte":
            return try lhs <= readNumber(spec.condition)
        case "btw", "nbtw":
            let (lower, upper) = try readNumberRange(spec.condition)
            let inRange = lhs >= lower && lhs <= upper
            return spec.condition.operator == "btw" ? inRange : !inRange
        default:
            throw EvaluationError.unsupportedOperator(
                propertyKey: spec.condition.propertyKey,
                operatorCode: spec.condition.operator,
            )
        }
    }

    func evaluateBoolean(spec: ConditionSpec, rawValue: Any?) throws -> Bool {
        guard spec.condition.operator == "eq" else {
            throw EvaluationError.unsupportedOperator(
                propertyKey: spec.condition.propertyKey,
                operatorCode: spec.condition.operator,
            )
        }

        guard let lhs = normalizedBoolean(rawValue) else {
            return false
        }

        return try lhs == readBool(spec.condition)
    }
}

private extension PostFilterEvaluator {
    func resolvePropertyValue(spec: ConditionSpec, context: inout PathContext) -> Any? {
        if let cached = context.propertyCache[spec.condition.propertyKey] {
            switch cached {
            case let .value(value): return value
            case .missing: return nil
            }
        }

        if let derived = derivedValue(for: spec.condition.propertyKey, context: &context) {
            context.propertyCache[spec.condition.propertyKey] = .value(derived)
            return derived
        }

        for key in spec.orderedSystemKeys {
            if let value = valueForSystemKey(key, context: &context) {
                context.propertyCache[spec.condition.propertyKey] = .value(value)
                return value
            }
        }

        context.propertyCache[spec.condition.propertyKey] = .missing
        return nil
    }

    func valueForSystemKey(
        _ key: SystemKey,
        context: inout PathContext,
    ) -> Any? {
        switch key.prefix {
        case "nsurl":
            valueForNSURLSymbol(key.symbol, context: &context)

        default:
            valueForMDItemSymbol(key.symbol, context: &context)
        }
    }

    func valueForNSURLSymbol(_ symbol: String, context: inout PathContext) -> Any? {
        if let cached = context.resourceCache[symbol] {
            switch cached {
            case let .value(value): return value
            case .missing: return nil
            }
        }

        let resourceKey = URLResourceKey(rawValue: symbol)
        do {
            let values = try context.url.resourceValues(forKeys: [resourceKey])
            if let value = values.allValues[resourceKey] {
                context.resourceCache[symbol] = .value(value)
                return value
            }
        } catch {
            context.resourceCache[symbol] = .missing
            return nil
        }

        context.resourceCache[symbol] = .missing
        return nil
    }

    func valueForMDItemSymbol(_ symbol: String, context: inout PathContext) -> Any? {
        if let cached = context.mdItemAttributeCache[symbol] {
            switch cached {
            case let .value(value): return value
            case .missing: return nil
            }
        }

        guard symbol.hasPrefix("kMD"), let mdItem = context.loadMDItem() else {
            context.mdItemAttributeCache[symbol] = .missing
            return nil
        }
        guard let value = MDItemCopyAttribute(mdItem, symbol as CFString) else {
            context.mdItemAttributeCache[symbol] = .missing
            return nil
        }
        context.mdItemAttributeCache[symbol] = .value(value)
        return value
    }

    func derivedValue(for propertyKey: String, context: inout PathContext) -> Any? {
        switch propertyKey {
        case "path":
            context.path
        case "extension":
            context.url.pathExtension
        case "name_stem":
            context.url.deletingPathExtension().lastPathComponent
        case "is_directory":
            derivedIsDirectory(context: &context)
        case "is_package":
            derivedIsPackage(context: &context)
        case "is_regular_file":
            derivedIsRegularFile(context: &context)
        case "is_symbolic_link":
            derivedIsSymbolicLink(context: &context)
        default:
            nil
        }
    }

    private struct MDItemTypeMetadata {
        let contentType: String?
        let contentTypeTree: Set<String>
    }

    private func mdItemTypeMetadata(context: inout PathContext) -> MDItemTypeMetadata? {
        let contentType = valueForMDItemSymbol("kMDItemContentType", context: &context) as? String
        let contentTypeTree = (valueForMDItemSymbol("kMDItemContentTypeTree", context: &context) as? [String]) ?? []
        if contentType == nil, contentTypeTree.isEmpty {
            return nil
        }
        return MDItemTypeMetadata(contentType: contentType, contentTypeTree: Set(contentTypeTree))
    }

    private func derivedIsDirectory(context: inout PathContext) -> Bool? {
        derivedTypeFlag(context: &context, evaluator: isDirectory)
    }

    private func derivedIsPackage(context: inout PathContext) -> Bool? {
        derivedTypeFlag(context: &context, evaluator: isPackage)
    }

    private func derivedIsRegularFile(context: inout PathContext) -> Bool? {
        guard let metadata = mdItemTypeMetadata(context: &context) else { return nil }
        let isFolder = isDirectory(metadata: metadata)
        let isLink = isSymbolicLink(metadata: metadata)
        return isFolder == false && isLink == false
    }

    private func derivedIsSymbolicLink(context: inout PathContext) -> Bool? {
        derivedTypeFlag(context: &context, evaluator: isSymbolicLink)
    }

    private func derivedTypeFlag(
        context: inout PathContext,
        evaluator: (MDItemTypeMetadata) -> Bool,
    ) -> Bool? {
        guard let metadata = mdItemTypeMetadata(context: &context) else { return nil }
        return evaluator(metadata)
    }

    private func isDirectory(metadata: MDItemTypeMetadata) -> Bool {
        if metadata.contentTypeTree.contains("public.folder") {
            return true
        }
        if let type = metadata.contentType.flatMap(UTType.init), type.conforms(to: .folder) {
            return true
        }
        return false
    }

    private func isPackage(metadata: MDItemTypeMetadata) -> Bool {
        if metadata.contentTypeTree.contains("com.apple.package") {
            return true
        }
        if let type = metadata.contentType.flatMap(UTType.init), type.conforms(to: .package) {
            return true
        }
        return false
    }

    private func isSymbolicLink(metadata: MDItemTypeMetadata) -> Bool {
        if metadata.contentTypeTree.contains("public.symlink") {
            return true
        }
        return metadata.contentType == "public.symlink"
    }
}
