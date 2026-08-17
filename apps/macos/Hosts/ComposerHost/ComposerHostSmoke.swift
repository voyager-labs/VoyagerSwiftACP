import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer

struct ComposerHostSmokeReport: Equatable {
    let presetCount: Int
    let registryPropertyCount: Int
    let registryCoverage: Bool
    let fixtureCorpusReady: Bool
    let fixtureEntryCount: Int
    let collectionCatalogReady: Bool
    let collectionDefinitionCount: Int
    let scenarioState: Bool
    let storeConstruction: Bool
    let rootConstruction: Bool
    let failureReason: String?

    var isValid: Bool {
        failureReason == nil
    }

    var lines: [String] {
        [
            "smokeMode=true",
            "presetCount=\(presetCount)",
            "registryPropertyCount=\(registryPropertyCount)",
            "registryCoverage=\(registryCoverage)",
            "fixtureCorpusReady=\(fixtureCorpusReady)",
            "fixtureEntryCount=\(fixtureEntryCount)",
            "collectionCatalogReady=\(collectionCatalogReady)",
            "collectionDefinitionCount=\(collectionDefinitionCount)",
            "scenarioState=\(scenarioState)",
            "storeConstruction=\(storeConstruction)",
            "rootConstruction=\(rootConstruction)",
        ]
    }
}

@MainActor
enum ComposerHostSmokeContract {
    static func validate() -> ComposerHostSmokeReport {
        let presets = ComposerHostPreset.allCases
        let registry = ComposerHostSandbox.makeRegistryClient()
        var failures: [String] = []
        var scenarioState = true
        var constructedStoreCount = 0
        var constructedRootCount = 0
        let fixtureResources = loadFixtureResources()

        for preset in presets {
            do {
                let state = try ComposerHostSandbox.makeInitialState(for: preset)
                if !state.isPresented || !state.isCollectionMode {
                    scenarioState = false
                    failures.append("preset_\(preset.rawValue)_not_interactive")
                }
            } catch {
                scenarioState = false
                failures.append("preset_\(preset.rawValue)_state_error")
            }

            let store = ComposerHostStoreContainer.makeStore(preset: preset, corpus: fixtureResources.corpus ?? .empty)
            constructedStoreCount += 1
            _ = ComposerHostRootView(store: store, preset: preset)
            constructedRootCount += 1
        }

        if !ComposerHostSandbox.registryCoverageIsComplete() {
            failures.append("registry_coverage_missing")
        }
        let storeConstruction = constructedStoreCount == presets.count
        let rootConstruction = constructedRootCount == presets.count
        if !storeConstruction {
            failures.append("store_construction_incomplete")
        }
        if !rootConstruction {
            failures.append("root_construction_incomplete")
        }
        if !fixtureResources.isReady {
            failures.append("fixture_resources_\(fixtureResources.failureReason ?? "unavailable")")
        }

        return .init(
            presetCount: presets.count,
            registryPropertyCount: registry.allProperties().count,
            registryCoverage: ComposerHostSandbox.registryCoverageIsComplete(),
            fixtureCorpusReady: fixtureResources.corpus != nil,
            fixtureEntryCount: fixtureResources.corpus?.entries.count ?? 0,
            collectionCatalogReady: fixtureResources.collections != nil,
            collectionDefinitionCount: fixtureResources.collections?.count ?? 0,
            scenarioState: scenarioState,
            storeConstruction: storeConstruction,
            rootConstruction: rootConstruction,
            failureReason: failures.isEmpty ? nil : failures.joined(separator: ","),
        )
    }

    private static func loadFixtureResources() -> ComposerHostSmokeFixtureResources {
        do {
            let root = try ComposerHostFixtureRootResolver.resolve()
            return try .init(
                corpus: ComposerHostFixtureCorpusLoader.load(root: root),
                collections: ComposerHostCollectionCatalog.discover(root: root),
                failureReason: nil,
            )
        } catch {
            return .init(corpus: nil, collections: nil, failureReason: error.localizedDescription)
        }
    }
}

private struct ComposerHostSmokeFixtureResources {
    let corpus: ComposerHostFixtureCorpus?
    let collections: [ComposerHostCollectionDefinition]?
    let failureReason: String?

    var isReady: Bool {
        corpus != nil && collections != nil
    }
}
