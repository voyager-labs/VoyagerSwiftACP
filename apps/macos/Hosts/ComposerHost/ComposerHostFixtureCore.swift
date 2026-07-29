import Foundation
@_spi(Testing)
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerShared

public enum ComposerHostFixtureRootResolver {
    nonisolated public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        maximumAscents: Int = 12,
    ) throws -> URL {
        if let projectRoot = environment["VOYAGER_PROJECT_ROOT"], !projectRoot.isEmpty {
            let root = URL(fileURLWithPath: projectRoot)
                .appendingPathComponent("fixtures/fixtures", isDirectory: true)
            return try validate(root)
        }

        var candidate = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        for _ in 0 ... maximumAscents {
            let root = candidate.appendingPathComponent("fixtures/fixtures", isDirectory: true)
            if let validated = try? validate(root) {
                return validated
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { break }
            candidate = parent
        }
        throw ComposerHostFixtureError.missingRoot(currentDirectoryPath)
    }

    nonisolated private static func validate(_ root: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.fileExists(
                  atPath: root.appendingPathComponent("collections").path,
                  isDirectory: &isDirectory,
              ),
              isDirectory.boolValue
        else {
            throw ComposerHostFixtureError.invalidRoot(root.path)
        }
        return root.standardizedFileURL
    }
}

public enum ComposerHostFixtureError: Error, Equatable, LocalizedError, Sendable {
    case missingRoot(String)
    case invalidRoot(String)
    case unreadableEntry(String)

    public var errorDescription: String? {
        switch self {
        case let .missingRoot(path): "Fixture root was not found while searching from \(path)."
        case let .invalidRoot(path): "Fixture root is invalid: \(path)."
        case let .unreadableEntry(path): "Fixture entry could not be read: \(path)."
        }
    }
}

public enum ComposerHostFixtureEntryType: String, Equatable, Sendable {
    case file
    case directory
    case package
}

public struct ComposerHostFixtureEntry: Equatable, Sendable, Identifiable {
    public let absolutePath: String
    public let relativePath: String
    public let name: String
    public let nameStem: String
    public let fileExtension: String
    public let corpusCategory: String
    public let entryType: ComposerHostFixtureEntryType
    public let kind: String
    public let size: Int64
    public let stableDate: Date
    public let tags: [String]
    public let isHidden: Bool
    public let isDirectory: Bool
    public let isPackage: Bool

    nonisolated public init(
        absolutePath: String,
        relativePath: String,
        name: String,
        nameStem: String,
        fileExtension: String,
        corpusCategory: String,
        entryType: ComposerHostFixtureEntryType,
        kind: String,
        size: Int64,
        stableDate: Date,
        tags: [String],
        isHidden: Bool,
        isDirectory: Bool,
        isPackage: Bool,
    ) {
        self.absolutePath = absolutePath
        self.relativePath = relativePath
        self.name = name
        self.nameStem = nameStem
        self.fileExtension = fileExtension
        self.corpusCategory = corpusCategory
        self.entryType = entryType
        self.kind = kind
        self.size = size
        self.stableDate = stableDate
        self.tags = tags
        self.isHidden = isHidden
        self.isDirectory = isDirectory
        self.isPackage = isPackage
    }

    public var id: String {
        absolutePath
    }
}

public struct ComposerHostFixtureCorpus: Equatable, Sendable {
    public let rootPath: String
    public let entries: [ComposerHostFixtureEntry]
    public let entriesByAbsolutePath: [String: ComposerHostFixtureEntry]

    nonisolated public init(rootPath: String, entries: [ComposerHostFixtureEntry]) {
        self.rootPath = (rootPath as NSString).standardizingPath
        self.entries = entries.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        entriesByAbsolutePath = Dictionary(uniqueKeysWithValues: self.entries.map { ($0.absolutePath, $0) })
    }

    public static let empty = ComposerHostFixtureCorpus(rootPath: "/", entries: [])
}

public enum ComposerHostFixtureCorpusLoader {
    nonisolated public static func load(root: URL) throws -> ComposerHostFixtureCorpus {
        let standardizedRoot = root.standardizedFileURL
        let collectionsURL = standardizedRoot.appendingPathComponent("collections", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .isHiddenKey],
            options: [],
        ) else {
            throw ComposerHostFixtureError.unreadableEntry(standardizedRoot.path)
        }

        var entries: [ComposerHostFixtureEntry] = []
        while let url = enumerator.nextObject() as? URL {
            let standardizedURL = url.standardizedFileURL
            if standardizedURL.path == collectionsURL.path || standardizedURL.path
                .hasPrefix(collectionsURL.path + "/")
            {
                enumerator.skipDescendants()
                continue
            }
            let values = try standardizedURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isPackageKey,
                .fileSizeKey,
                .isHiddenKey,
            ])
            let isDirectory = values.isDirectory == true
            let isPackage = isDirectory &&
                (values.isPackage == true || standardizedURL.pathExtension.lowercased() == "voycoll")
            if isPackage {
                try entries.append(makeEntry(
                    url: standardizedURL,
                    root: standardizedRoot,
                    values: values,
                    packageSize: packageSize(at: standardizedURL),
                ))
                enumerator.skipDescendants()
            } else {
                try entries.append(makeEntry(
                    url: standardizedURL,
                    root: standardizedRoot,
                    values: values,
                    packageSize: nil,
                ))
            }
        }
        return .init(rootPath: standardizedRoot.path, entries: entries)
    }

    nonisolated private static func makeEntry(
        url: URL,
        root: URL,
        values: URLResourceValues,
        packageSize: Int64?,
    ) throws -> ComposerHostFixtureEntry {
        let relativePath = String(url.path.dropFirst(root.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else { throw ComposerHostFixtureError.unreadableEntry(url.path) }
        let isDirectory = values.isDirectory == true
        let isPackage = isDirectory && (values.isPackage == true || url.pathExtension.lowercased() == "voycoll")
        let entryType: ComposerHostFixtureEntryType = isPackage ? .package : (isDirectory ? .directory : .file)
        let extensionName = url.pathExtension.lowercased()
        let corpusCategory = relativePath.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "root"
        return .init(
            absolutePath: url.standardizedFileURL.path,
            relativePath: relativePath,
            name: url.lastPathComponent,
            nameStem: url.deletingPathExtension().lastPathComponent,
            fileExtension: extensionName,
            corpusCategory: corpusCategory,
            entryType: entryType,
            kind: kind(for: entryType, extensionName: extensionName, corpusCategory: corpusCategory),
            size: packageSize ?? Int64(values.fileSize ?? 0),
            stableDate: stableDate(for: relativePath),
            tags: stableTags(for: relativePath, corpusCategory: corpusCategory),
            isHidden: values.isHidden == true || url.lastPathComponent.hasPrefix("."),
            isDirectory: isDirectory,
            isPackage: isPackage,
        )
    }

    nonisolated private static func packageSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
        ) else { return 0 }
        var total: Int64 = 0
        while let child = enumerator.nextObject() as? URL {
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    nonisolated private static func kind(
        for entryType: ComposerHostFixtureEntryType,
        extensionName: String,
        corpusCategory: String,
    ) -> String {
        switch entryType {
        case .directory: "Folder"
        case .package: "\(corpusCategory.capitalized) Package"
        case .file:
            switch extensionName {
            case "pdf": "PDF"
            case "jpg", "jpeg", "png", "gif", "heic": "Image"
            case "txt", "md", "rtf": "Text"
            case "swift", "py", "js", "ts", "json", "yaml", "yml": "Source"
            case "zip", "tar", "gz": "Archive"
            default: extensionName.isEmpty ? "File" : extensionName.uppercased()
            }
        }
    }

    nonisolated private static func stableDate(for relativePath: String) -> Date {
        Date(timeIntervalSince1970: 1_704_067_200 + TimeInterval(stableDigest(relativePath) % 31_536_000))
    }

    nonisolated private static func stableTags(for relativePath: String, corpusCategory: String) -> [String] {
        let digest = stableDigest(relativePath)
        let options = ["Work", "Pinned", "Archive"]
        let first = options[Int(digest % UInt64(options.count))]
        let second = options[Int((digest / 7) % UInt64(options.count))]
        return Array(Set([corpusCategory.capitalized, first, second])).sorted()
    }

    nonisolated private static func stableDigest(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

public struct ComposerHostFixtureSearchPolicy: Equatable, Sendable {
    public let includeDirectories: Bool

    nonisolated public init(includeDirectories: Bool = false) {
        self.includeDirectories = includeDirectories
    }
}

private typealias FixtureEntry = ComposerHostFixtureEntry

public enum ComposerHostFixtureEvaluator {
    nonisolated private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    nonisolated public static func evaluate(
        corpus: ComposerHostFixtureCorpus,
        query: String,
        filters: SearchFiltersPayload,
        policy: ComposerHostFixtureSearchPolicy,
    ) -> [ComposerHostFixtureEntry] {
        corpus.entries.filter { entry in
            (policy.includeDirectories || entry.entryType == .package || !entry.isDirectory)
                && matchesScope(entry, filters: filters)
                && (!filters.includeSubfolders || !hasScope(entry, in: filters.excludedScopes, includeSubfolders: true))
                && matchesQuery(entry, query: query)
                && filters.conditions.allSatisfy { matches(entry, $0) }
        }
    }

    nonisolated private static func matchesScope(_ entry: FixtureEntry, filters: SearchFiltersPayload) -> Bool {
        filters.scopes.isEmpty || hasScope(entry, in: filters.scopes, includeSubfolders: filters.includeSubfolders)
    }

    nonisolated private static func hasScope(
        _ entry: ComposerHostFixtureEntry,
        in scopes: [String],
        includeSubfolders: Bool,
    ) -> Bool {
        scopes.contains { scope in
            let standardized = (scope as NSString).standardizingPath
            if includeSubfolders {
                return entry.absolutePath == standardized || entry.absolutePath.hasPrefix(standardized + "/")
            }
            let parentPath = (entry.absolutePath as NSString).deletingLastPathComponent
            return parentPath == standardized
        }
    }

    nonisolated private static func matchesQuery(_ entry: ComposerHostFixtureEntry, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return [entry.relativePath, entry.name, entry.fileExtension, entry.entryType.rawValue, entry.corpusCategory]
            .contains { $0.lowercased().contains(needle) }
    }

    nonisolated private static func matches(_ entry: FixtureEntry, _ condition: SearchConditionPayload) -> Bool {
        let key = ComposerHostFixtureConditionNormalization.canonicalPropertyKey(condition.propertyKey)
        let operation = ComposerHostFixtureConditionNormalization.canonicalOperator(condition.operator)
        let values = ComposerHostFixtureConditionNormalization.values(from: condition.value)
        switch key {
        case "name_stem": return matchesName(entry, operation: operation, values: values)
        case "extension": return matchesString(entry.fileExtension, operation: operation, values: values)
        case "kind": return matchesString(entry.kind, operation: operation, values: values)
        case "file_size": return matchesNumber(entry.size, operation: operation, values: values)
        case "modified_date", "created_date": return matchesDate(entry.stableDate, operation: operation, values: values)
        case "tag_names": return matchesTags(entry.tags, operation: operation, values: values)
        case "is_hidden": return matchesBool(entry.isHidden, operation: operation, values: values)
        default: return false
        }
    }

    nonisolated private static func matchesString(_ actual: String, operation: String, values: [String]) -> Bool {
        if let presence = matchesPresence(isEmpty: actual.isEmpty, operation: operation) {
            return presence
        }
        let normalized = actual.lowercased()
        let expected = values.map { $0.lowercased() }
        if ["all", "none", "miss"].contains(operation) {
            return matchesStringList(normalized, operation: operation, expected: expected)
        }
        return matchesSingleString(normalized, operation: operation, expected: expected)
    }

    nonisolated private static func matchesSingleString(
        _ actual: String, operation: String, expected: [String],
    ) -> Bool {
        switch operation {
        case "cn": expected.contains { actual.contains($0) }
        case "nc": expected.allSatisfy { !actual.contains($0) }
        case "sw": expected.contains { actual.hasPrefix($0) }
        case "ew": expected.contains { actual.hasSuffix($0) }
        case "eq", "in", "any": expected.contains(actual)
        case "neq": !expected.contains(actual)
        default: false
        }
    }

    nonisolated private static func matchesStringList(_ actual: String, operation: String, expected: [String]) -> Bool {
        switch operation {
        case "all": expected.allSatisfy(actual.contains)
        case "none": expected.allSatisfy { !actual.contains($0) }
        case "miss": expected.contains { !actual.contains($0) }
        default: false
        }
    }

    nonisolated private static func matchesName(
        _ entry: FixtureEntry,
        operation: String,
        values: [String],
    ) -> Bool {
        matchesString(operation == "cn" ? entry.name : entry.nameStem, operation: operation, values: values)
    }

    nonisolated private static func matchesNumber(_ actual: Int64, operation: String, values: [String]) -> Bool {
        if let presence = matchesPresence(isEmpty: false, operation: operation) {
            return presence
        }
        let numbers = values.compactMap(Double.init)
        return matchesNumberComparison(Double(actual), operation: operation, numbers: numbers)
    }

    nonisolated private static func matchesNumberComparison(
        _ actual: Double, operation: String, numbers: [Double],
    ) -> Bool {
        switch operation {
        case "eq": numbers.first == actual
        case "neq": numbers.first.map { actual != $0 } ?? false
        case "gt": numbers.first.map { actual > $0 } ?? false
        case "gte": numbers.first.map { actual >= $0 } ?? false
        case "lt": numbers.first.map { actual < $0 } ?? false
        case "lte": numbers.first.map { actual <= $0 } ?? false
        case "btw": matchesRange(actual, numbers: numbers)
        case "nbtw": numbers.count == 2 && !matchesRange(actual, numbers: numbers)
        default: false
        }
    }

    nonisolated private static func matchesRange(_ actual: Double, numbers: [Double]) -> Bool {
        guard numbers.count == 2 else { return false }
        return actual >= min(numbers[0], numbers[1]) && actual <= max(numbers[0], numbers[1])
    }

    nonisolated private static func matchesDate(_ actual: Date, operation: String, values: [String]) -> Bool {
        if let presence = matchesPresence(isEmpty: false, operation: operation) {
            return presence
        }
        if operation == "today" {
            return isSameDay(actual, Date())
        }
        let formatter = ISO8601DateFormatter()
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dates = values.compactMap { formatter.date(from: $0) ?? dateFormatter.date(from: $0) }
        return matchesDateComparison(actual, operation: operation, dates: dates)
    }

    nonisolated private static func matchesDateComparison(_ actual: Date, operation: String, dates: [Date]) -> Bool {
        switch operation {
        case "eq": dates.first.map { isSameDay(actual, $0) } ?? false
        case "neq": dates.first.map { !isSameDay(actual, $0) } ?? false
        case "gt": dates.first.flatMap(dayInterval).map { actual >= $0.end } ?? false
        case "gte": dates.first.flatMap(dayInterval).map { actual >= $0.start } ?? false
        case "lt": dates.first.flatMap(dayInterval).map { actual < $0.start } ?? false
        case "lte": dates.first.flatMap(dayInterval).map { actual < $0.end } ?? false
        case "btw": matchesDateRange(actual, dates: dates)
        case "nbtw": dates.count == 2 && !matchesDateRange(actual, dates: dates)
        default: false
        }
    }

    nonisolated private static func matchesDateRange(_ actual: Date, dates: [Date]) -> Bool {
        guard dates.count == 2,
              let first = dayInterval(dates[0]),
              let second = dayInterval(dates[1])
        else { return false }
        return actual >= min(first.start, second.start) && actual < max(first.end, second.end)
    }

    nonisolated private static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    nonisolated private static func dayInterval(_ date: Date) -> DateInterval? {
        calendar.dateInterval(of: .day, for: date)
    }

    nonisolated private static func matchesTags(_ actual: [String], operation: String, values: [String]) -> Bool {
        if let presence = matchesPresence(isEmpty: actual.isEmpty, operation: operation) {
            return presence
        }
        let actual = actual.map { $0.lowercased() }
        let expected = values.map { $0.lowercased() }
        return switch operation {
        case "cn", "eq", "in", "any": actual.contains { expected.contains($0) }
        case "neq", "none": actual.allSatisfy { !expected.contains($0) }
        case "all": expected.allSatisfy(actual.contains)
        case "miss": expected.contains { !actual.contains($0) }
        default: false
        }
    }

    nonisolated private static func matchesBool(_ actual: Bool, operation: String, values: [String]) -> Bool {
        if let presence = matchesPresence(isEmpty: false, operation: operation) {
            return presence
        }
        return switch operation {
        case "eq": values.first.map { $0.lowercased() == String(actual) } ?? false
        case "neq": values.first.map { $0.lowercased() != String(actual) } ?? false
        default: false
        }
    }

    nonisolated private static func matchesPresence(isEmpty: Bool, operation: String) -> Bool? {
        switch operation {
        case "exists": !isEmpty
        case "empty": isEmpty
        default: nil
        }
    }
}

public enum ComposerHostFixtureConditionNormalization {
    nonisolated private static let operatorAliases = [
        "eq": "eq", "equals": "eq", "is": "eq",
        "neq": "neq", "notequals": "neq", "isnot": "neq",
        "cn": "cn", "contains": "cn",
        "nc": "nc", "notcontains": "nc",
        "sw": "sw", "startswith": "sw", "beginswith": "sw",
        "ew": "ew", "endswith": "ew",
        "in": "in",
        "gt": "gt", "greaterthan": "gt", "after": "gt",
        "gte": "gte", "greaterthanorequal": "gte", "greaterorequal": "gte",
        "lt": "lt", "lessthan": "lt", "before": "lt",
        "lte": "lte", "lessthanorequal": "lte", "lessorequal": "lte",
        "exists": "exists", "empty": "empty",
        "any": "any", "all": "all", "none": "none", "miss": "miss",
        "btw": "btw", "between": "btw", "nbtw": "nbtw", "notbetween": "nbtw",
        "today": "today",
    ]

    nonisolated public static func canonicalPropertyKey(_ key: String) -> String {
        switch normalizedAlias(key) {
        case "name", "namestem": "name_stem"
        case "extension", "fileextension": "extension"
        case "kind", "filekind": "kind"
        case "size", "filesize": "file_size"
        case "created", "createddate", "creationdate": "created_date"
        case "modified", "modifieddate", "modificationdate": "modified_date"
        case "tag", "tagnames": "tag_names"
        case "hidden", "ishidden", "isinvisible": "is_hidden"
        default: key
        }
    }

    nonisolated public static func canonicalOperator(_ value: String) -> String {
        operatorAliases[normalizedAlias(value)] ?? value
    }

    nonisolated public static func values(from value: JSONValue?) -> [String] {
        switch value {
        case let .string(string):
            string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case let .array(values): values.compactMap(stringValue)
        case let .number(number): [String(number)]
        case let .bool(value): [String(value)]
        case .object, .null, nil: []
        }
    }

    nonisolated public static func normalized(_ condition: CollectionCondition) -> SearchConditionPayload {
        let operation = canonicalOperator(condition.operatorCode)
        return .init(
            propertyKey: canonicalPropertyKey(condition.propertyKey),
            operator: operation,
            value: normalizedValue(condition.value, operation: operation),
        )
    }

    nonisolated private static func normalizedAlias(_ value: String) -> String {
        value.lowercased().filter { $0 != "_" && $0 != "-" && !$0.isWhitespace }
    }

    nonisolated private static func normalizedValue(_ value: JSONValue?, operation: String) -> JSONValue? {
        guard let value else { return nil }
        if operation == "in" || operation == "any", case .string = value {
            return .array(values(from: value).map(JSONValue.string))
        }
        return value
    }

    nonisolated private static func stringValue(_ value: JSONValue) -> String? {
        switch value {
        case let .string(string): string
        case let .number(number): String(number)
        case let .bool(value): String(value)
        case .array, .object, .null: nil
        }
    }
}

public enum ComposerHostFixtureSearchClientFactory {
    nonisolated public static func make(
        corpus: ComposerHostFixtureCorpus,
        policy: ComposerHostFixtureSearchPolicy = .init(),
    ) -> SearchClient {
        let response: @Sendable (String, SearchFiltersPayload) -> SearchResponsePayload = { query, filters in
            let filters = remapSyntheticFixtureScopes(filters, corpusRootPath: corpus.rootPath)
            let entries = ComposerHostFixtureEvaluator.evaluate(
                corpus: corpus,
                query: query,
                filters: filters,
                policy: policy,
            )
            return .init(
                itemCount: entries.count,
                appliedFilters: .init(
                    scopes: filters.scopes,
                    excludedScopes: filters.excludedScopes,
                    includeSubfolders: filters.includeSubfolders,
                    conditions: filters.conditions,
                ),
                items: entries.map { .string($0.absolutePath) },
                error: nil,
                queryConversion: .init(outcome: .unchangedResult),
            )
        }
        var client = SearchClient.testValue
        client.search = { request in response(request.query, request.filters) }
        client.applyFilters = { request in response("", request.filters) }
        client.warmUpAIModelCatalog = {}
        return client
    }

    nonisolated private static func remapSyntheticFixtureScopes(
        _ filters: SearchFiltersPayload,
        corpusRootPath: String,
    ) -> SearchFiltersPayload {
        .init(
            scopes: filters.scopes.map { remapSyntheticFixtureScope($0, corpusRootPath: corpusRootPath) },
            excludedScopes: filters.excludedScopes
                .map { remapSyntheticFixtureScope($0, corpusRootPath: corpusRootPath) },
            includeSubfolders: filters.includeSubfolders,
            conditions: filters.conditions,
        )
    }

    nonisolated private static func remapSyntheticFixtureScope(_ scope: String, corpusRootPath: String) -> String {
        let standardizedScope = (scope as NSString).standardizingPath
        guard standardizedScope == "/Fixture" || standardizedScope.hasPrefix("/Fixture/")
        else { return standardizedScope }
        if standardizedScope == "/Fixture/Documents" {
            return (corpusRootPath + "/documents" as NSString).standardizingPath
        }
        let suffix = standardizedScope.dropFirst("/Fixture".count)
        return (corpusRootPath + String(suffix) as NSString).standardizingPath
    }
}

public struct ComposerHostCollectionDefinition: Equatable, Sendable, Identifiable {
    public let url: URL
    public let name: String
    public let isPackage: Bool

    nonisolated public init(url: URL, name: String, isPackage: Bool) {
        self.url = url
        self.name = name
        self.isPackage = isPackage
    }

    public var id: String {
        url.path
    }
}

public struct ComposerHostRestoredCollectionDraft: Equatable, Sendable {
    public let definition: ComposerHostCollectionDefinition
    public let payload: CollectionDraftRestorePayload
    public let searchPolicy: ComposerHostFixtureSearchPolicy
    public let diagnostics: [String]

    nonisolated public init(
        definition: ComposerHostCollectionDefinition,
        payload: CollectionDraftRestorePayload,
        searchPolicy: ComposerHostFixtureSearchPolicy,
        diagnostics: [String],
    ) {
        self.definition = definition
        self.payload = payload
        self.searchPolicy = searchPolicy
        self.diagnostics = diagnostics
    }

    public var blocksExecution: Bool {
        !diagnostics.isEmpty || payload.context.conditions.contains { !$0.isExecutionReady }
    }
}

public enum ComposerHostCollectionCatalog {
    nonisolated public static func discover(root: URL) throws -> [ComposerHostCollectionDefinition] {
        let collections = root.appendingPathComponent("collections", isDirectory: true).standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: collections,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [],
        ) else { throw ComposerHostFixtureError.unreadableEntry(collections.path) }
        var definitions: [ComposerHostCollectionDefinition] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isDirectory = values.isDirectory == true
            let isPackage = isDirectory && (values.isPackage == true || url.pathExtension.lowercased() == "voycoll")
            if url.pathExtension.lowercased() == "voycoll" {
                definitions.append(.init(
                    url: url.standardizedFileURL,
                    name: url.deletingPathExtension().lastPathComponent,
                    isPackage: isPackage,
                ))
                if isDirectory { enumerator.skipDescendants() }
            }
        }
        return definitions.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    nonisolated public static func load(
        definition: ComposerHostCollectionDefinition,
        fixtureRoot: URL,
        registryClient: RegistryClient,
    ) async throws -> ComposerHostRestoredCollectionDraft {
        let loaded = try await CollectionFileClient.liveValue.load(definition.url)
        let remappedScopes = [fixtureRoot.standardizedFileURL.path]
        let exclusionRemapping = remapExclusions(loaded.file.excludedScopes, fixtureRoot: fixtureRoot)
        let remappedExclusions = exclusionRemapping.scopes
        let conditions = loaded.file.conditions.map {
            SearchConditionPayload(
                propertyKey: $0.propertyKey,
                operator: $0.operatorCode,
                value: $0.value,
            )
        }
        let resolved = AppliedFilterResolver.resolveDetailed(
            .init(
                scopes: remappedScopes,
                excludedScopes: remappedExclusions,
                includeSubfolders: loaded.file.includeSubfolders,
                conditions: conditions,
            ),
            fallbackScopes: remappedScopes,
            fallbackConditions: [],
            registryClient: registryClient,
            fallbackExcludedScopes: remappedExclusions,
        )
        var diagnostics = exclusionRemapping.diagnostics + resolved.unknownKeys.map { "Unsupported property: \($0)" }
        diagnostics += resolved.conditions.compactMap { condition in
            if condition.availability == .invalidPersistedValue {
                return "Invalid condition: \(condition.property.key)"
            }
            if condition.availability != .available {
                return "Unavailable condition: \(condition.property.key)"
            }
            return condition.isExecutionReady ? nil : "Invalid condition: \(condition.property.key)"
        }
        let context = CollectionContext(
            query: loaded.file.query,
            scopes: remappedScopes,
            excludedScopes: remappedExclusions,
            includeSubfolders: loaded.file.includeSubfolders,
            includeDirectories: loaded.file.includeDirectories,
            conditions: resolved.conditions,
        )
        return .init(
            definition: definition,
            payload: .init(context: context, openedURL: definition.url),
            searchPolicy: .init(includeDirectories: loaded.file.includeDirectories),
            diagnostics: diagnostics.sorted(),
        )
    }

    nonisolated private static func remapExclusions(
        _ exclusions: [String],
        fixtureRoot: URL,
    ) -> (scopes: [String], diagnostics: [String]) {
        let rootPath = fixtureRoot.standardizedFileURL.path
        var diagnostics: [String] = []
        let remapped = exclusions.compactMap { exclusion -> String? in
            let standardized = (exclusion as NSString).standardizingPath
            let remappedScope: String
            if standardized == rootPath || standardized.hasPrefix(rootPath + "/") {
                remappedScope = standardized
            } else if standardized == "/VoyagerFixtures/Documents/Archive" {
                remappedScope = ((rootPath + "/archives") as NSString).standardizingPath
            } else if standardized == "/VoyagerFixtures" || standardized.hasPrefix("/VoyagerFixtures/") {
                let suffix = standardized.dropFirst("/VoyagerFixtures".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                remappedScope = suffix.isEmpty ? rootPath : ((rootPath + "/" + suffix) as NSString).standardizingPath
            } else if let range = standardized.range(of: "/fixtures/fixtures") {
                let suffix = standardized[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                remappedScope = suffix.isEmpty ? rootPath : ((rootPath + "/" + suffix) as NSString).standardizingPath
            } else {
                diagnostics.append("Unmappable excluded scope: \(exclusion)")
                return nil
            }
            guard FileManager.default.fileExists(atPath: remappedScope) else {
                diagnostics.append("Excluded scope does not exist: \(remappedScope)")
                return nil
            }
            return remappedScope
        }
        return (remapped.sorted(), diagnostics.sorted())
    }
}

public enum ComposerHostCollectionRestoreError: Error, Equatable, LocalizedError, Sendable {
    case unmappableExclusions([String])

    public var errorDescription: String? {
        switch self {
        case let .unmappableExclusions(diagnostics): diagnostics.joined(separator: "; ")
        }
    }
}
