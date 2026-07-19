import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences

// 상태 조립은 public RegistryClient 경로를 쓰고 fixture resolver만 test SPI로 Condition을 구성한다.
@_spi(Testing)
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesComposer
import VoyagerShared

public enum ComposerHostSandbox {
    public static let documentsPath = "/Fixture/Documents"
    public static let projectsPath = "/Fixture/Projects"
    public static let downloadsPath = "/Fixture/Downloads"
    public static let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)

    public static let favorites: [ScopeFavoriteItem] = [
        .init(name: "Documents", url: URL(fileURLWithPath: documentsPath), iconName: "doc"),
        .init(name: "Projects", url: URL(fileURLWithPath: projectsPath), iconName: "folder"),
        .init(name: "Downloads", url: URL(fileURLWithPath: downloadsPath), iconName: "arrow.down.circle"),
    ]

    public static let historyPaths = [projectsPath, downloadsPath]

    public static func dependencies(for _: ComposerHostPreset) -> DependencyValues {
        var dependencies = DependencyValues()
        configure(&dependencies)
        return dependencies
    }

    public static func configure(
        _ dependencies: inout DependencyValues,
        corpus: ComposerHostFixtureCorpus = loadFixtureCorpusOrEmpty(),
        searchPolicy: ComposerHostFixtureSearchPolicy = .init(),
    ) {
        dependencies.registryClient = makeRegistryClient()
        dependencies.searchClient = makeSearchClient(corpus: corpus, policy: searchPolicy)
        dependencies.entryLoadingClient = makeEntryLoadingClient()
        dependencies.finderFavoritesTagClient = makeFinderFavoritesTagClient()
        dependencies.uuid = .incrementing
        dependencies.date = .constant(referenceDate)
        dependencies.continuousClock = ImmediateClock()
        dependencies.composerMetricClient = .testValue
        dependencies.collectionSearchAISettingsClient = .init(
            load: { .default },
            save: { _ in },
            reset: {},
        )
    }

    public static func makeInitialState(
        for preset: ComposerHostPreset,
        fixtureRootPath: String? = nil,
    ) throws -> ComposerState {
        let registry = makeRegistryClient()
        var state = ComposerState()
        state.isPresented = true
        state.isCollectionMode = true
        state.scopes = [fixtureRootPath ?? documentsPath]

        if preset == .propertyMenu {
            state.propertyPicker.isPresented = true
        }
        if let fixture = conditionFixtures[preset] {
            try appendCondition(fixture, to: &state, registry: registry)
        }

        return state
    }

    public static func makeInitialState(for draft: ComposerHostRestoredCollectionDraft) -> ComposerState {
        var state = ComposerState()
        state.isPresented = true
        state.isCollectionMode = true
        state.applyCollectionDraftRestorePayload(draft.payload)
        return state
    }

    public static func loadFixtureCorpus() throws -> ComposerHostFixtureCorpus {
        try ComposerHostFixtureCorpusLoader.load(root: ComposerHostFixtureRootResolver.resolve())
    }

    public static func registryCoverageIsComplete() -> Bool {
        let registry = makeRegistryClient()
        let keys = Set(registry.allProperties().map(\.key))
        return keys.isSuperset(of: ["kind", "modified_date", "file_size", "tag_names"])
            && Set(registry.operatorCodes(for: "kind")).isSuperset(of: ["eq", "exists"])
            && Set(registry.operatorCodes(for: "modified_date")).isSuperset(of: ["eq", "btw", "exists"])
            && Set(registry.operatorCodes(for: "file_size")).isSuperset(of: ["eq", "btw"])
            && Set(registry.operatorCodes(for: "tag_names")).contains("any")
    }

    private static func appendCondition(
        _ fixture: ConditionFixture,
        to state: inout ComposerState,
        registry: RegistryClient,
    ) throws {
        let condition = try registry.resolveCondition(
            propertyKey: fixture.propertyKey,
            operatorCode: fixture.operatorCode,
            values: fixture.values,
            sourcePayload: nil,
        )
        guard let id = UUID(uuidString: fixture.id) else {
            preconditionFailure("ComposerHost fixture UUID is invalid")
        }
        state.conditionEditors.append(.init(id: id, condition: condition))
    }
}

extension ComposerHostSandbox {
    struct ConditionFixture {
        let propertyKey: String
        let operatorCode: String
        let values: [String]
        let id: String
    }

    static let conditionFixtures: [ComposerHostPreset: ConditionFixture] = [
        .textValue: .init(
            propertyKey: "name_stem",
            operatorCode: "eq",
            values: ["Voyager"],
            id: "00000000-0000-0000-0000-000000000101",
        ),
        .numberRange: .init(
            propertyKey: "file_size",
            operatorCode: "btw",
            values: ["1048576", "5242880"],
            id: "00000000-0000-0000-0000-000000000102",
        ),
        .boolean: .init(
            propertyKey: "is_hidden",
            operatorCode: "eq",
            values: ["false"],
            id: "00000000-0000-0000-0000-000000000103",
        ),
        .tokenList: .init(
            propertyKey: "tag_names",
            operatorCode: "any",
            values: ["Work", "Pinned"],
            id: "00000000-0000-0000-0000-000000000104",
        ),
        .dateRange: .init(
            propertyKey: "modified_date",
            operatorCode: "btw",
            values: ["2025-01-01", "2025-01-31"],
            id: "00000000-0000-0000-0000-000000000105",
        ),
    ]

    static func makeRegistryClient() -> RegistryClient {
        let properties = registryProperties
        let operatorDefinitions = registryOperatorDefinitions
        let propertyEntries = properties.map(\.entry)
        let labelsByKey = Dictionary(uniqueKeysWithValues: properties.map { ($0.key, $0.label) })
        let typesByKey = Dictionary(uniqueKeysWithValues: properties.map { ($0.key, $0.type.rawValue) })
        let unitSpecsByKey = Dictionary(uniqueKeysWithValues: properties.compactMap { property in
            property.unitSpec.map { (property.key, $0) }
        })
        let operatorCodesByKey = Dictionary(uniqueKeysWithValues: properties.map { ($0.key, $0.operatorCodes) })
        let contractsByKey = Dictionary(uniqueKeysWithValues: properties.map { ($0.key, $0.contracts) })
        let canonicalConditionPropertiesByKey = Dictionary(uniqueKeysWithValues: properties.map {
            ($0.key, $0.conditionProperty)
        })
        let conditionPropertiesByKey = Dictionary(uniqueKeysWithValues: properties.flatMap { property in
            ([property.key] + registryPropertyAliases[property.key, default: []])
                .map { ($0, property.conditionProperty) }
        })
        let resolver = ComposerHostRegistryResolver(
            conditionPropertiesByKey: conditionPropertiesByKey,
            contractsByKey: contractsByKey,
            operatorDefinitions: operatorDefinitions,
        )

        return .init(
            allProperties: { propertyEntries },
            labelForKey: { labelsByKey[$0] ?? $0 },
            propertyTypeString: { typesByKey[$0] ?? "unknown" },
            propertyUnitSpec: { unitSpecsByKey[$0] },
            operatorCodes: { operatorCodesByKey[$0] ?? [] },
            operatorDefinition: { operatorDefinitions[$0] ?? .init(uiLabel: $0) },
            resolvePropertyKey: { key in
                let canonicalKey = ComposerHostFixtureConditionNormalization.canonicalPropertyKey(key)
                guard canonicalConditionPropertiesByKey[canonicalKey] != nil else { return .unknown(key) }
                return canonicalKey == key ? .canonical(canonicalKey) : .legacy(original: key, normalized: canonicalKey)
            },
            resolveCondition: resolver.resolveCondition,
        )
    }

    static func makeSearchClient(
        corpus: ComposerHostFixtureCorpus = loadFixtureCorpusOrEmpty(),
        policy: ComposerHostFixtureSearchPolicy = .init(),
    ) -> SearchClient {
        ComposerHostFixtureSearchClientFactory.make(corpus: corpus, policy: policy)
    }

    public static func loadFixtureCorpusOrEmpty() -> ComposerHostFixtureCorpus {
        (try? loadFixtureCorpus()) ?? .empty
    }

    static func favorites(for corpus: ComposerHostFixtureCorpus) -> [ScopeFavoriteItem] {
        let root = URL(fileURLWithPath: corpus.rootPath)
        return [
            .init(name: "Documents", url: root.appendingPathComponent("documents"), iconName: "doc"),
            .init(
                name: "Presentations",
                url: root.appendingPathComponent("presentations"),
                iconName: "rectangle.on.rectangle",
            ),
            .init(name: "Archives", url: root.appendingPathComponent("archives"), iconName: "archivebox"),
        ]
    }

    static func historyPaths(for corpus: ComposerHostFixtureCorpus) -> [String] {
        let root = URL(fileURLWithPath: corpus.rootPath)
        return [
            root.appendingPathComponent("presentations").path,
            root.appendingPathComponent("archives").path,
        ]
    }

    static func makeEntryLoadingClient() -> EntryLoadingClient {
        let documentsPath = Self.documentsPath
        let projectsPath = Self.projectsPath
        let downloadsPath = Self.downloadsPath
        let referenceDate = Self.referenceDate
        let directories = Set([documentsPath, projectsPath, downloadsPath])
        let children = [
            documentsPath: [URL(fileURLWithPath: "\(documentsPath)/Plans")],
            projectsPath: [URL(fileURLWithPath: "\(projectsPath)/Composer")],
            downloadsPath: [],
        ]
        return .init(
            loadItems: { _, _ in [] },
            loadComputerItems: { [] },
            loadRecentItems: { _, _ in [] },
            loadFilesWithTag: { _, _, _ in [] },
            fileExists: { directories.contains($0) },
            fileExistsAtPath: { path, isDirectory in
                let exists = directories.contains(path)
                isDirectory?.pointee = ObjCBool(exists)
                return exists
            },
            contentsOfDirectory: { url, _, _ in children[url.path] ?? [] },
            mountedVolumeURLs: { _, _ in [] },
            urlsForDirectory: { directory, _ in
                switch directory {
                case .documentDirectory:
                    [URL(fileURLWithPath: documentsPath)]
                case .downloadsDirectory:
                    [URL(fileURLWithPath: downloadsPath)]
                default:
                    []
                }
            },
            homeDirectory: { "/Fixture" },
            getItemMetadata: { _, _, _ in
                .init(kind: "Fixture", creatorApplication: nil, lastUsedDate: referenceDate)
            },
            getImageResolution: { _ in nil },
            getFileSizeInBytes: { _ in nil },
            getFolderItemCount: { _ in nil },
            isPackageDirectory: { _ in false },
            displayName: { path in URL(fileURLWithPath: path).lastPathComponent },
        )
    }

    static func makeFinderFavoritesTagClient() -> FinderFavoritesTagClient {
        let tags = [
            Tag(name: "Work", colorCode: 4),
            Tag(name: "Pinned", colorCode: 0),
            Tag(name: "Archive", colorCode: 6),
        ]
        return .init(
            favoriteTagNames: { tags.map(\.name) },
            favoriteTags: { tags },
        )
    }
}

nonisolated private struct ComposerHostRegistryResolver {
    let conditionPropertiesByKey: [String: Condition.Property]
    let contractsByKey: [String: [String: Condition.ValueContract]]
    let operatorDefinitions: [String: OperatorDefinition]

    func resolveCondition(
        propertyKey: String,
        operatorCode: String?,
        values: [String]?,
        sourcePayload: CollectionCondition?,
    ) -> Condition {
        let canonicalPropertyKey = ComposerHostFixtureConditionNormalization.canonicalPropertyKey(propertyKey)
        let canonicalOperatorCode = operatorCode.map(ComposerHostFixtureConditionNormalization.canonicalOperator)
        guard let conditionProperty = conditionPropertiesByKey[canonicalPropertyKey] else {
            return Condition(
                property: .init(
                    key: propertyKey,
                    label: propertyKey,
                    type: .unknown,
                    unitContract: nil,
                    operatorOptions: [],
                ),
                operation: nil,
                values: nil,
                availability: .unsupportedProperty,
                opaqueSource: sourcePayload,
            )
        }

        let operation = canonicalOperatorCode.flatMap { code -> Condition.Operation? in
            guard let contract = contractsByKey[canonicalPropertyKey]?[code] else { return nil }
            return .init(
                code: code,
                label: operatorDefinitions[code]?.uiLabel ?? code,
                valueContract: contract,
            )
        }
        let availability: Condition.Availability = canonicalOperatorCode == nil || operation != nil
            ? .available
            : .unsupportedOperator
        let normalizedValues = operation?.valueContract.count == .fixed(0) ? [] : values

        return Condition(
            property: conditionProperty,
            operation: operation,
            values: normalizedValues,
            availability: availability,
            opaqueSource: availability == .available ? nil : sourcePayload,
        )
    }
}

private extension ComposerHostSandbox {
    struct RegistryProperty {
        let key: String
        let label: String
        let category: String
        let type: SystemPropertyTypeKey
        let operatorCodes: [String]
        let contracts: [String: Condition.ValueContract]
        let unitContract: Condition.UnitContract?
        let unitSpec: SystemPropertyUnitSpec?

        var entry: RegistrySnapshot.PropertyEntry {
            .init(key: key, category: category, definition: definition)
        }

        var conditionProperty: Condition.Property {
            .init(
                key: key,
                label: label,
                type: type,
                unitContract: unitContract,
                operatorOptions: operatorCodes.map {
                    .init(code: $0, label: ComposerHostSandbox.registryOperatorDefinitions[$0]?.uiLabel ?? $0)
                },
            )
        }

        private var definition: SystemPropertyDefinition {
            let unitFragment = unitSpec == nil ? "" : """
            ,
              "unit_spec": {
                "canonical_unit": "bytes",
                "units": [
                  { "code": "bytes", "label": "Bytes", "factor_to_canonical": "1" },
                  { "code": "kb", "label": "KB", "factor_to_canonical": "1024" },
                  { "code": "mb", "label": "MB", "factor_to_canonical": "1048576" }
                ],
                "default_display_unit": "mb"
              }
            """
            let json = """
            {
              "ui_label": "\(label)",
              "description": "ComposerHost deterministic fixture",
              "type": "\(type.rawValue)",
              "system_keys": []\(unitFragment)
            }
            """
            do {
                return try JSONDecoder().decode(SystemPropertyDefinition.self, from: Data(json.utf8))
            } catch {
                preconditionFailure("ComposerHost registry fixture is invalid: \(error)")
            }
        }
    }

    static let registryProperties: [RegistryProperty] = [
        .init(
            key: "kind",
            label: "Kind",
            category: "General",
            type: .categorical,
            operatorCodes: ["eq", "in", "exists"],
            contracts: [
                "eq": .init(shape: .single, count: .fixed(1), input: .singleText),
                "in": .init(shape: .list, count: .multiple, input: .listText),
                "exists": .init(shape: .none, count: .fixed(0), input: .none),
            ],
            unitContract: nil,
            unitSpec: nil,
        ),
        .init(
            key: "name_stem",
            label: "Name",
            category: "General",
            type: .string,
            operatorCodes: ["eq", "contains", "in", "exists"],
            contracts: [
                "eq": .init(shape: .single, count: .fixed(1), input: .singleText),
                "contains": .init(shape: .single, count: .fixed(1), input: .singleText),
                "in": .init(shape: .list, count: .multiple, input: .listText),
                "exists": .init(shape: .none, count: .fixed(0), input: .none),
            ],
            unitContract: nil,
            unitSpec: nil,
        ),
        .init(
            key: "extension",
            label: "Extension",
            category: "General",
            type: .categorical,
            operatorCodes: ["eq", "in", "exists"],
            contracts: [
                "eq": .init(shape: .single, count: .fixed(1), input: .singleText),
                "in": .init(shape: .list, count: .multiple, input: .listText),
                "exists": .init(shape: .none, count: .fixed(0), input: .none),
            ],
            unitContract: nil,
            unitSpec: nil,
        ),
        .init(
            key: "modified_date",
            label: "Modified Date",
            category: "General",
            type: .date,
            operatorCodes: ["eq", "before", "after", "btw", "exists"],
            contracts: [
                "eq": .init(shape: .single, count: .fixed(1), input: .singleDate),
                "before": .init(shape: .single, count: .fixed(1), input: .singleDate),
                "after": .init(shape: .single, count: .fixed(1), input: .singleDate),
                "btw": .init(shape: .range, count: .fixed(2), input: .rangeDate),
                "exists": .init(shape: .none, count: .fixed(0), input: .none),
            ],
            unitContract: nil,
            unitSpec: nil,
        ),
        .init(
            key: "created_date",
            label: "Created Date",
            category: "General",
            type: .date,
            operatorCodes: ["eq", "before", "after", "btw", "exists"],
            contracts: [
                "eq": .init(shape: .single, count: .fixed(1), input: .singleDate),
                "before": .init(shape: .single, count: .fixed(1), input: .singleDate),
                "after": .init(shape: .single, count: .fixed(1), input: .singleDate),
                "btw": .init(shape: .range, count: .fixed(2), input: .rangeDate),
                "exists": .init(shape: .none, count: .fixed(0), input: .none),
            ],
            unitContract: nil,
            unitSpec: nil,
        ),
        .init(
            key: "file_size",
            label: "File Size",
            category: "General",
            type: .number,
            operatorCodes: ["eq", "gt", "btw"],
            contracts: [
                "eq": .init(shape: .single, count: .fixed(1), input: .singleNumber),
                "gt": .init(shape: .single, count: .fixed(1), input: .singleNumber),
                "btw": .init(shape: .range, count: .fixed(2), input: .rangeNumber),
            ],
            unitContract: .init(
                canonicalUnit: "bytes",
                options: [
                    .init(code: "bytes", label: "Bytes", factorToCanonical: 1),
                    .init(code: "kb", label: "KB", factorToCanonical: 1024),
                    .init(code: "mb", label: "MB", factorToCanonical: 1_048_576),
                ],
                defaultDisplayUnit: "mb",
            ),
            unitSpec: makeFileSizeUnitSpec(),
        ),
        .init(
            key: "is_hidden",
            label: "Is Hidden",
            category: "General",
            type: .boolean,
            operatorCodes: ["eq"],
            contracts: ["eq": .init(shape: .single, count: .fixed(1), input: .toggle)],
            unitContract: nil,
            unitSpec: nil,
        ),
        .init(
            key: "tag_names",
            label: "Tag Names",
            category: "General",
            type: .categorical,
            operatorCodes: ["eq", "contains", "in", "any", "exists"],
            contracts: [
                "eq": .init(shape: .single, count: .fixed(1), input: .singleText),
                "contains": .init(shape: .single, count: .fixed(1), input: .singleText),
                "in": .init(shape: .list, count: .multiple, input: .listText),
                "any": .init(shape: .list, count: .multiple, input: .listText),
                "exists": .init(shape: .none, count: .fixed(0), input: .none),
            ],
            unitContract: nil,
            unitSpec: nil,
        ),
    ]

    static let registryOperatorDefinitions: [String: OperatorDefinition] = [
        "eq": .init(uiLabel: "Is"),
        "contains": .init(uiLabel: "Contains"),
        "in": .init(uiLabel: "Is Any Of"),
        "gt": .init(uiLabel: "Greater Than"),
        "before": .init(uiLabel: "Before"),
        "after": .init(uiLabel: "After"),
        "btw": .init(uiLabel: "Between"),
        "exists": .init(uiLabel: "Exists"),
        "any": .init(uiLabel: "Includes Any"),
    ]

    static let registryPropertyAliases: [String: [String]] = [
        "name_stem": ["name"],
        "extension": ["file_extension"],
        "kind": ["file_kind"],
        "file_size": ["size"],
        "created_date": ["created", "creation_date"],
        "modified_date": ["modified", "modification_date"],
        "tag_names": ["tag"],
        "is_hidden": ["hidden"],
    ]

    static func makeFileSizeUnitSpec() -> SystemPropertyUnitSpec {
        let json = """
        {
          "canonical_unit": "bytes",
          "units": [
            { "code": "bytes", "label": "Bytes", "factor_to_canonical": "1" },
            { "code": "kb", "label": "KB", "factor_to_canonical": "1024" },
            { "code": "mb", "label": "MB", "factor_to_canonical": "1048576" }
          ],
          "default_display_unit": "mb"
        }
        """
        do {
            return try JSONDecoder().decode(SystemPropertyUnitSpec.self, from: Data(json.utf8))
        } catch {
            preconditionFailure("ComposerHost unit fixture is invalid: \(error)")
        }
    }
}
