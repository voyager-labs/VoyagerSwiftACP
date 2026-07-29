import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerFeaturesComposer
import VoyagerShared

public struct ComposerHostRootView: View {
    @ObservedObject private var container: ComposerHostStoreContainer

    public init(container: ComposerHostStoreContainer) {
        _container = ObservedObject(wrappedValue: container)
    }

    public init(store: StoreOf<ComposerFeature>, preset: ComposerHostPreset) {
        self.init(container: .init(store: store, preset: preset))
    }

    public var body: some View {
        WithViewStore(container.store, observe: ComposerHostStatus.init) { viewStore in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(container.preset.title)
                        .font(.caption.weight(.semibold))
                    Text("conditions=\(viewStore.conditionCount)")
                    Text("scopes=\(viewStore.scopeCount)")
                    Text("items=\(viewStore.lastItemCount.map(String.init) ?? "-")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Composer host status")

                ComposerView(
                    store: container.store,
                    favorites: container.favorites,
                    historyPaths: container.historyPaths,
                    isDiscardEnabled: false,
                    canSaveCollection: false,
                    isTemporaryCollection: true,
                    onDiscardCollectionChanges: {},
                    onExitComposer: {},
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                ComposerHostResultPanel(
                    response: viewStore.response,
                    fixtureState: container.fixtureState,
                    collectionState: container.collectionState,
                    selectedCollection: container.selectedCollection,
                    diagnostics: container.diagnostics,
                )
            }
            .padding(12)
            .frame(minWidth: 640, minHeight: 360, alignment: .topLeading)
        }
    }
}

private struct ComposerHostStatus: Equatable {
    let conditionCount: Int
    let scopeCount: Int
    let lastItemCount: Int?
    let response: SearchResponsePayload?

    init(state: ComposerState) {
        conditionCount = state.conditions.count
        scopeCount = state.scopes.count
        response = state.lastFiltersResponse ?? state.lastSearchResponse
        lastItemCount = response?.itemCount
    }
}

private struct ComposerHostResultPanel: View {
    let response: SearchResponsePayload?
    let fixtureState: ComposerHostFixtureState
    let collectionState: ComposerHostCollectionState
    let selectedCollection: ComposerHostCollectionDefinition?
    let diagnostics: [String]

    var body: some View {
        let projection = ComposerHostResultProjection(response: response, fixtureState: fixtureState)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Fixture results")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(projection.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Fixture result summary: \(projection.summary)")
            }

            Text(fixtureDescription)
                .font(.caption)
                .foregroundStyle(fixtureState.isFailure ? .red : .secondary)
                .accessibilityLabel("Fixture corpus status: \(fixtureDescription)")

            Text("Collection: \(selectedCollection?.name ?? "Preset")")
                .font(.caption)
                .foregroundStyle(.secondary)

            if case .loading = collectionState {
                Text("Loading selected Collection…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = projection.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Fixture result error: \(error)")
            }

            diagnosticList(diagnostics + projection.diagnostics)
            resultContent(projection)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var fixtureDescription: String {
        switch fixtureState {
        case .loading:
            "Fixture corpus loading…"
        case let .ready(corpus, collections):
            "Fixture corpus ready: \(corpus.entries.count) entries, \(collections.count) Collections"
        case let .failed(message):
            "Fixture corpus unavailable: \(message). Initialize the fixtures submodule and relaunch."
        }
    }

    @ViewBuilder
    private func diagnosticList(_ messages: [String]) -> some View {
        let uniqueMessages = Array(Set(messages)).sorted()
        if !uniqueMessages.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(uniqueMessages, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Composer host diagnostic: \(message)")
                }
            }
        }
    }

    @ViewBuilder
    private func resultContent(_ projection: ComposerHostResultProjection) -> some View {
        if response == nil {
            Text("Run a query or apply filters to inspect fixture paths.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if projection.rows.isEmpty, projection.errorMessage == nil {
            Text("No matching fixtures.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !projection.rows.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(projection.rows) { row in
                        HStack(spacing: 8) {
                            Text(row.relativePath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(row.kind)
                                .foregroundStyle(.secondary)
                            Text(row.formattedSize)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 58, alignment: .trailing)
                        }
                        .font(.caption.monospaced())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.relativePath), \(row.kind), \(row.formattedSize)")
                    }
                }
            }
            .frame(maxHeight: 240)
        }
    }
}

private struct ComposerHostResultProjection: Equatable {
    let rows: [ComposerHostResultRow]
    let diagnostics: [String]
    let responseCount: Int?
    let errorMessage: String?

    init(response: SearchResponsePayload?, fixtureState: ComposerHostFixtureState) {
        responseCount = response?.itemCount
        errorMessage = response?.error.map { error in
            error.details.map { "Search error (\(error.code)): \($0)" } ?? "Search error: \(error.code)"
        }
        guard let response, let corpus = fixtureState.corpus else {
            rows = []
            diagnostics = []
            return
        }

        var rows: [ComposerHostResultRow] = []
        var diagnostics: [String] = []
        for (index, item) in (response.items ?? []).enumerated() {
            guard case let .string(path) = item else {
                diagnostics.append("Malformed response item at position \(index + 1): expected a path string.")
                continue
            }
            let standardizedPath = (path as NSString).standardizingPath
            guard let entry = corpus.entriesByAbsolutePath[standardizedPath] else {
                diagnostics.append("Response path is not in the fixture corpus: \(path)")
                continue
            }
            rows.append(.init(index: index, entry: entry))
        }
        self.rows = rows
        self.diagnostics = diagnostics
    }

    var summary: String {
        guard let responseCount else { return "No response" }
        return "\(responseCount) results"
    }
}

private struct ComposerHostResultRow: Equatable, Identifiable {
    let id: String
    let relativePath: String
    let kind: String
    let formattedSize: String

    init(index: Int, entry: ComposerHostFixtureEntry) {
        id = "\(index)-\(entry.absolutePath)"
        relativePath = entry.relativePath
        kind = entry.kind
        formattedSize = Self.byteCountFormatter.string(fromByteCount: entry.size)
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = false
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}

private extension ComposerHostFixtureState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
