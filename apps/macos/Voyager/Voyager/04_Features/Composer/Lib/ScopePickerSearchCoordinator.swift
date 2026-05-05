import Combine
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

@MainActor
final class ScopePickerSearchCoordinator: ObservableObject {
    enum ListState {
        case defaultList([ComposerScopeUtils.DirectoryItem])
        case searchResults([ComposerScopeUtils.DirectoryItem])
        case noResults
    }

    @Published private(set) var listState: ListState

    private let entryLoadingClient: EntryLoadingClient
    private let favorites: [ScopeFavoriteItem]
    private let backHistory: [String]
    private var searchTask: Task<Void, Never>?

    init(
        entryLoadingClient: EntryLoadingClient,
        favorites: [ScopeFavoriteItem],
        backHistory: [String],
    ) {
        self.entryLoadingClient = entryLoadingClient
        self.favorites = favorites
        self.backHistory = backHistory
        listState = .defaultList(
            ComposerScopeUtils.buildCombinedList(
                history: backHistory,
                favorites: favorites,
                entryLoadingClient: entryLoadingClient,
                maxCount: 10,
            ),
        )
    }

    func update(query: String) {
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            listState = .defaultList(
                ComposerScopeUtils.buildCombinedList(
                    history: backHistory,
                    favorites: favorites,
                    entryLoadingClient: entryLoadingClient,
                    maxCount: 10,
                ),
            )
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let loadingClient = entryLoadingClient
            let searchQuery = trimmedQuery
            let results = try? await Task.detached(priority: .userInitiated) {
                try await ComposerScopeUtils.searchDirectories(
                    query: searchQuery,
                    entryLoadingClient: loadingClient,
                    maxResults: 50,
                    initialMaxDepth: 2,
                    timeout: 2.0,
                )
            }.value

            guard !Task.isCancelled else { return }
            if let results, !results.isEmpty {
                listState = .searchResults(results)
            } else {
                listState = .noResults
            }
        }
    }

    func stop() {
        searchTask?.cancel()
        searchTask = nil
    }
}
