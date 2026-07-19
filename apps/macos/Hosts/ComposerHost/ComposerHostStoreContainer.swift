import Combine
import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer

public enum ComposerHostFixtureState: Equatable {
    case loading
    case ready(corpus: ComposerHostFixtureCorpus, collections: [ComposerHostCollectionDefinition])
    case failed(message: String)

    var corpus: ComposerHostFixtureCorpus? {
        guard case let .ready(corpus, _) = self else { return nil }
        return corpus
    }

    var collections: [ComposerHostCollectionDefinition] {
        guard case let .ready(_, collections) = self else { return [] }
        return collections
    }
}

public enum ComposerHostCollectionState: Equatable {
    case idle
    case loading
    case ready
    case failed(message: String)
}

@MainActor
public final class ComposerHostStoreContainer: ObservableObject {
    @Published public private(set) var store: StoreOf<ComposerFeature>
    @Published public private(set) var preset: ComposerHostPreset
    @Published public private(set) var scenarioID: String
    @Published public private(set) var fixtureState: ComposerHostFixtureState
    @Published public private(set) var collectionState: ComposerHostCollectionState = .idle
    @Published public private(set) var selectedCollection: ComposerHostCollectionDefinition?
    @Published public private(set) var diagnostics: [String] = []

    private var collectionSelectionGeneration = 0
    private var storeGeneration = 0

    public init(preset: ComposerHostPreset = .empty) {
        self.preset = preset
        scenarioID = preset.scenario.id
        fixtureState = .loading
        store = Self.makeStore(preset: preset, corpus: .empty)
        loadFixtures()
    }

    init(store: StoreOf<ComposerFeature>, preset: ComposerHostPreset) {
        self.store = store
        self.preset = preset
        scenarioID = preset.scenario.id
        fixtureState = .loading
    }

    public func select(_ preset: ComposerHostPreset) {
        self.preset = preset
        selectedCollection = nil
        collectionState = .idle
        diagnostics = []
        collectionSelectionGeneration &+= 1
        replaceStore(with: Self.makeStore(preset: preset, corpus: fixtureState.corpus ?? .empty))
    }

    public func selectCollection(id: String?) {
        collectionSelectionGeneration &+= 1
        let generation = collectionSelectionGeneration

        guard let id else {
            selectedCollection = nil
            collectionState = .idle
            diagnostics = []
            replaceStore(with: Self.makeStore(preset: preset, corpus: fixtureState.corpus ?? .empty))
            return
        }

        guard case let .ready(corpus, collections) = fixtureState,
              let definition = collections.first(where: { $0.id == id })
        else {
            collectionState = .failed(message: "Fixture corpus is not ready.")
            diagnostics = ["Saved Collections are available after the fixture corpus finishes loading."]
            return
        }

        collectionState = .loading
        diagnostics = []
        let fixtureRoot = URL(fileURLWithPath: corpus.rootPath)
        let registryClient = ComposerHostSandbox.makeRegistryClient()
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                await Self.loadCollection(
                    definition: definition,
                    fixtureRoot: fixtureRoot,
                    registryClient: registryClient,
                )
            }
            .value
            guard let self, collectionSelectionGeneration == generation else { return }
            applyCollection(outcome, corpus: corpus)
        }
    }

    var collections: [ComposerHostCollectionDefinition] {
        fixtureState.collections
    }

    var canSelectCollections: Bool {
        !collections.isEmpty
    }

    var favorites: [ScopeFavoriteItem] {
        guard let corpus = fixtureState.corpus else { return ComposerHostSandbox.favorites }
        return ComposerHostSandbox.favorites(for: corpus)
    }

    var historyPaths: [String] {
        guard let corpus = fixtureState.corpus else { return ComposerHostSandbox.historyPaths }
        return ComposerHostSandbox.historyPaths(for: corpus)
    }

    static func makeStore(
        preset: ComposerHostPreset,
        corpus: ComposerHostFixtureCorpus = .empty,
        searchPolicy: ComposerHostFixtureSearchPolicy = .init(),
    ) -> StoreOf<ComposerFeature> {
        let initialState: ComposerState
        do {
            initialState = try ComposerHostSandbox.makeInitialState(
                for: preset,
                fixtureRootPath: corpus.entries.isEmpty ? nil : corpus.rootPath,
            )
        } catch {
            preconditionFailure("ComposerHost preset '\(preset.rawValue)' is invalid: \(error)")
        }

        return makeStore(initialState: initialState, corpus: corpus, searchPolicy: searchPolicy)
    }

    private static func makeStore(
        initialState: ComposerState,
        corpus: ComposerHostFixtureCorpus,
        searchPolicy: ComposerHostFixtureSearchPolicy,
    ) -> StoreOf<ComposerFeature> {
        Store(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            ComposerHostSandbox.configure(&$0, corpus: corpus, searchPolicy: searchPolicy)
        }
    }

    private func loadFixtures() {
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.loadFixtureResources()
            }
            .value
            guard let self else { return }
            switch outcome {
            case let .ready(corpus, collections):
                fixtureState = .ready(corpus: corpus, collections: collections)
                replaceStore(with: Self.makeStore(preset: preset, corpus: corpus))
            case let .failed(message):
                fixtureState = .failed(message: message)
                diagnostics = ["Fixture setup required: initialize the fixtures submodule, then relaunch ComposerHost."]
            }
        }
    }

    private func replaceStore(with store: StoreOf<ComposerFeature>) {
        self.store = store
        storeGeneration &+= 1
        scenarioID = "\(preset.scenario.id)-\(storeGeneration)"
    }

    private func applyCollection(
        _ outcome: ComposerHostCollectionLoadOutcome,
        corpus: ComposerHostFixtureCorpus,
    ) {
        switch outcome {
        case let .ready(draft):
            var initialState = ComposerHostSandbox.makeInitialState(for: draft)
            initialState.text = draft.payload.context.query
            selectedCollection = draft.definition
            diagnostics = draft.diagnostics
            collectionState = .ready
            replaceStore(with: Self.makeStore(
                initialState: initialState,
                corpus: corpus,
                searchPolicy: draft.searchPolicy,
            ))

            guard !draft.blocksExecution else { return }
            if !draft.payload.context.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.send(.submit)
            } else if !initialState.conditions.isEmpty {
                store.send(.applyFilters)
            }

        case let .failed(definition, message):
            collectionState = .failed(message: message)
            diagnostics = ["Could not load \(definition.name): \(message)"]
        }
    }

    nonisolated private static func loadFixtureResources() -> ComposerHostFixtureLoadOutcome {
        do {
            let root = try ComposerHostFixtureRootResolver.resolve()
            let corpus = try ComposerHostFixtureCorpusLoader.load(root: root)
            let collections = try ComposerHostCollectionCatalog.discover(root: root)
            return .ready(corpus: corpus, collections: collections)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    nonisolated private static func loadCollection(
        definition: ComposerHostCollectionDefinition,
        fixtureRoot: URL,
        registryClient: RegistryClient,
    ) async -> ComposerHostCollectionLoadOutcome {
        do {
            return try await .ready(ComposerHostCollectionCatalog.load(
                definition: definition,
                fixtureRoot: fixtureRoot,
                registryClient: registryClient,
            ))
        } catch {
            return .failed(definition: definition, message: error.localizedDescription)
        }
    }
}

private enum ComposerHostFixtureLoadOutcome {
    case ready(corpus: ComposerHostFixtureCorpus, collections: [ComposerHostCollectionDefinition])
    case failed(message: String)
}

private enum ComposerHostCollectionLoadOutcome {
    case ready(ComposerHostRestoredCollectionDraft)
    case failed(definition: ComposerHostCollectionDefinition, message: String)
}
