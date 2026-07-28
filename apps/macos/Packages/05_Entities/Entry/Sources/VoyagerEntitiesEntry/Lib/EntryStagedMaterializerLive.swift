import Dependencies
import Foundation
import VoyagerEntitiesTag
import VoyagerShared

public enum EntryMetadataProbe: CaseIterable, Equatable, Sendable {
    case spotlight
    case tags
    case supplementaryMetadata
}

public struct EntryMetadataPriority: Equatable, Sendable {
    public let probes: [EntryMetadataProbe]

    public static let none = EntryMetadataPriority(orderedProbes: [])

    public static func active(_ probes: [EntryMetadataProbe]) -> EntryMetadataPriority {
        EntryMetadataPriority(orderedProbes: (probes + EntryMetadataProbe.allCases).reduce(into: []) { result, probe in
            if !result.contains(probe) {
                result.append(probe)
            }
        })
    }

    private init(orderedProbes: [EntryMetadataProbe]) {
        probes = orderedProbes
    }
}

public enum EntryMetadataPatch: Equatable, Sendable {
    case spotlight(id: EntryModel.ID, kind: String?, creatorApplication: String?, lastOpenedDate: Date?)
    case tags(id: EntryModel.ID, tags: [Tag]?)
    case supplementaryMetadata(id: EntryModel.ID, metadata: EntrySupplementaryMetadata?)
}

public enum EntryLoadEvent: Equatable, Sendable {
    case coreBatch(items: [EntryModel], batchIndex: Int)
    case coreFinished(batchCount: Int)
    case metadataPatches([EntryMetadataPatch])
}

public enum EntryStagedMaterializerLive {
    struct URLMaterializationConfiguration {
        let priority: EntryMetadataPriority
        let entryLoadingClient: EntryLoadingClient
        let workspaceClient: WorkspaceClient
        let sourceKind: EntryLoadingSourceKind
        let instrumentation: EntryLoadingInstrumentation
        let favoriteTags: [Tag]
    }

    public static let batchSize = 32

    public static func materializeURLs(
        _ urls: [URL],
        showHidden: Bool,
        priority: EntryMetadataPriority,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
    ) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        @Dependency(\.finderFavoritesTagClient) var finderFavoritesTagClient
        return materializeURLs(
            urls,
            showHidden: showHidden,
            configuration: .init(
                priority: priority,
                entryLoadingClient: entryLoadingClient,
                workspaceClient: workspaceClient,
                sourceKind: .direct,
                instrumentation: .live(),
                favoriteTags: finderFavoritesTagClient.favoriteTags(),
            ),
        )
    }

    public static func materializePayloadEntries(
        _ entries: [EntryModel],
        showHidden: Bool,
    ) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        materializePayloadEntries(
            entries,
            showHidden: showHidden,
            sourceKind: .direct,
            instrumentation: .live(),
        )
    }

    static func materializeURLs(
        _ urls: [URL],
        showHidden: Bool,
        configuration: URLMaterializationConfiguration,
    ) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        let sequence = URLMaterializationSequence(
            urls: urls,
            showHidden: showHidden,
            priority: configuration.priority,
            entryLoadingClient: configuration.entryLoadingClient,
            workspaceClient: configuration.workspaceClient,
            favoriteTags: configuration.favoriteTags,
            context: .init(
                sourceKind: configuration.sourceKind,
                correlationID: UUID(),
                inputCount: urls.count,
                priority: configuration.priority.instrumentationValue,
            ),
            instrumentation: configuration.instrumentation,
        )
        return AsyncThrowingStream(unfolding: { await sequence.next() })
    }

    static func materializePayloadEntries(
        _ entries: [EntryModel],
        showHidden: Bool,
        sourceKind: EntryLoadingSourceKind,
        instrumentation: EntryLoadingInstrumentation,
    ) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        let sequence = URLMaterializationSequence(
            entries: filtered(entries, showHidden: showHidden),
            priority: .none,
            entryLoadingClient: .testValue,
            workspaceClient: .testValue,
            favoriteTags: [],
            context: .init(
                sourceKind: sourceKind,
                correlationID: UUID(),
                inputCount: entries.count,
                priority: EntryMetadataPriority.none.instrumentationValue,
            ),
            instrumentation: instrumentation,
        )
        return AsyncThrowingStream(unfolding: { await sequence.next() })
    }

    private static func filtered(_ entries: [EntryModel], showHidden: Bool) -> [EntryModel] {
        var seen = Set<EntryModel.ID>()
        return entries.filter { entry in
            guard showHidden || !entry.isHidden, seen.insert(entry.id).inserted else { return false }
            return true
        }
    }
}

private actor URLMaterializationSequence {
    private let urls: [URL]?
    private let sourceEntries: [EntryModel]
    private let showHidden: Bool
    private let priority: EntryMetadataPriority
    private let entryLoadingClient: EntryLoadingClient
    private let workspaceClient: WorkspaceClient
    private let favoriteTags: [Tag]
    private let context: EntryLoadingInstrumentation.Context
    private let instrumentation: EntryLoadingInstrumentation
    private var entries: [EntryModel] = []
    private var sourceIndex = 0
    private var batchIndex = 0
    private var probeIndex = 0
    private var seenIDs = Set<EntryModel.ID>()
    private var workCounts: EntryLoadingInstrumentation.WorkCounts
    private var didFinishCore = false
    private var didCloseFirstCoreBatch = false
    private var didCloseCoreComplete = false
    private var didCloseRequest = false
    private var didBeginMetadata = false
    private var didFinish = false

    init(
        urls: [URL]?,
        sourceEntries: [EntryModel],
        showHidden: Bool,
        priority: EntryMetadataPriority,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
        favoriteTags: [Tag],
        context: EntryLoadingInstrumentation.Context,
        instrumentation: EntryLoadingInstrumentation,
    ) {
        self.urls = urls
        self.sourceEntries = sourceEntries
        self.showHidden = showHidden
        self.priority = priority
        self.entryLoadingClient = entryLoadingClient
        self.workspaceClient = workspaceClient
        self.favoriteTags = favoriteTags
        self.context = context
        self.instrumentation = instrumentation
        workCounts = .init(validEntries: 0, batchCount: 0, folderCountProbes: 0)
        instrumentation.begin(.request, context: context)
        instrumentation.begin(.firstCoreBatch, context: context)
        instrumentation.begin(.coreComplete, context: context)
    }

    init(
        entries: [EntryModel],
        priority: EntryMetadataPriority,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
        favoriteTags: [Tag],
        context: EntryLoadingInstrumentation.Context,
        instrumentation: EntryLoadingInstrumentation,
    ) {
        self.init(
            urls: nil,
            sourceEntries: entries,
            showHidden: true,
            priority: priority,
            entryLoadingClient: entryLoadingClient,
            workspaceClient: workspaceClient,
            favoriteTags: favoriteTags,
            context: context,
            instrumentation: instrumentation,
        )
    }

    init(
        urls: [URL],
        showHidden: Bool,
        priority: EntryMetadataPriority,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
        favoriteTags: [Tag],
        context: EntryLoadingInstrumentation.Context,
        instrumentation: EntryLoadingInstrumentation,
    ) {
        self.init(
            urls: urls,
            sourceEntries: [],
            showHidden: showHidden,
            priority: priority,
            entryLoadingClient: entryLoadingClient,
            workspaceClient: workspaceClient,
            favoriteTags: favoriteTags,
            context: context,
            instrumentation: instrumentation,
        )
    }

    func next() async -> EntryLoadEvent? {
        guard !Task.isCancelled else {
            finishIfNeeded()
            return nil
        }

        if !didFinishCore {
            return await nextCoreEvent()
        }

        return nextMetadataEvent()
    }

    private func nextMetadataEvent() -> EntryLoadEvent? {
        guard probeIndex < priority.probes.count else {
            finishIfNeeded()
            return nil
        }
        beginMetadataIfNeeded()
        while probeIndex < priority.probes.count {
            guard !Task.isCancelled else {
                finishIfNeeded()
                return nil
            }

            let probe = priority.probes[probeIndex]
            probeIndex += 1
            var patches: [EntryMetadataPatch] = []
            for entry in entries {
                guard !Task.isCancelled else {
                    finishIfNeeded()
                    return nil
                }

                if probe == .supplementaryMetadata, entry.isFolder {
                    workCounts.folderCountProbes += 1
                }
                if let patch = EntryModelConverterLive.metadataPatch(
                    for: entry,
                    probe: probe,
                    entryLoadingClient: entryLoadingClient,
                    workspaceClient: workspaceClient,
                    favoriteTags: favoriteTags,
                ) {
                    patches.append(patch)
                }

                guard !Task.isCancelled else {
                    finishIfNeeded()
                    return nil
                }
            }
            if !patches.isEmpty {
                return .metadataPatches(patches)
            }
        }
        finishIfNeeded()
        return nil
    }

    private func nextCoreEvent() async -> EntryLoadEvent? {
        while true {
            guard !Task.isCancelled else {
                finishIfNeeded()
                return nil
            }

            var batch: [EntryModel] = []
            if let urls {
                let chunkEndIndex = min(sourceIndex + EntryStagedMaterializerLive.batchSize, urls.count)
                while sourceIndex < chunkEndIndex {
                    let url = urls[sourceIndex]
                    sourceIndex += 1
                    guard let entry = EntryModelConverterLive.convertURLToCoreEntry(
                        url,
                        entryLoadingClient: entryLoadingClient,
                    ) else { continue }
                    guard showHidden || !entry.isHidden, seenIDs.insert(entry.id).inserted else { continue }
                    batch.append(entry)
                }
            } else if sourceIndex < sourceEntries.count {
                let endIndex = min(sourceIndex + EntryStagedMaterializerLive.batchSize, sourceEntries.count)
                batch = Array(sourceEntries[sourceIndex ..< endIndex])
                sourceIndex = endIndex
            }

            if !batch.isEmpty {
                entries.append(contentsOf: batch)
                workCounts.validEntries += batch.count
                workCounts.batchCount += 1
                closeFirstCoreBatchIfNeeded()
                defer { batchIndex += 1 }
                return .coreBatch(items: batch, batchIndex: batchIndex)
            }

            if sourceIndex >= (urls?.count ?? sourceEntries.count) {
                didFinishCore = true
                closeFirstCoreBatchIfNeeded()
                closeCoreCompleteIfNeeded()
                closeRequestIfNeeded()
                return .coreFinished(batchCount: batchIndex)
            }

            await Task.yield()
        }
    }

    private func closeFirstCoreBatchIfNeeded() {
        guard !didCloseFirstCoreBatch else { return }
        didCloseFirstCoreBatch = true
        instrumentation.end(.firstCoreBatch, context: context, workCounts: workCounts)
    }

    private func closeCoreCompleteIfNeeded() {
        guard !didCloseCoreComplete else { return }
        didCloseCoreComplete = true
        instrumentation.end(.coreComplete, context: context, workCounts: workCounts)
    }

    private func beginMetadataIfNeeded() {
        guard !didBeginMetadata else { return }
        didBeginMetadata = true
        instrumentation.begin(.metadataComplete, context: context)
    }

    private func closeRequestIfNeeded() {
        guard !didCloseRequest else { return }
        didCloseRequest = true
        instrumentation.end(.request, context: context, workCounts: workCounts)
    }

    private func finishIfNeeded() {
        guard !didFinish else { return }
        didFinish = true
        closeFirstCoreBatchIfNeeded()
        closeCoreCompleteIfNeeded()
        closeRequestIfNeeded()
        if didBeginMetadata {
            instrumentation.end(.metadataComplete, context: context, workCounts: workCounts)
        }
    }
}
