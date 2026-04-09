import ComposableArchitecture
import Foundation

public struct FinderFavoritesTagClient: Sendable {
    public var favoriteTagNames: @Sendable () -> [String]
    public var favoriteTags: @Sendable () -> [Tag]

    nonisolated init(
        favoriteTagNames: @escaping @Sendable () -> [String],
        favoriteTags: @escaping @Sendable () -> [Tag],
    ) {
        self.favoriteTagNames = favoriteTagNames
        self.favoriteTags = favoriteTags
    }
}

extension FinderFavoritesTagClient: DependencyKey {
    public nonisolated static var liveValue: FinderFavoritesTagClient {
        let favoriteTagNamesLoader: @Sendable () -> [String] = {
            guard let finderDefaults = UserDefaults(suiteName: "com.apple.finder"),
                  let tagNames = finderDefaults.array(forKey: "FavoriteTagNames") as? [String]
            else {
                return []
            }
            return tagNames
        }

        let favoriteTagsLoader: @Sendable () -> [Tag] = {
            let rawNames = favoriteTagNamesLoader()
            let usesLeadingPlaceholderSlot = rawNames.count > 7 &&
                rawNames.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true

            return rawNames.enumerated().compactMap { index, rawName -> Tag? in
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                let finderFavoriteSlotIndex = usesLeadingPlaceholderSlot ? index - 1 : index

                return Tag(
                    name: name,
                    colorCode: TagColor(finderFavoriteSlotIndex: finderFavoriteSlotIndex).rawValue,
                )
            }
        }

        return FinderFavoritesTagClient(
            favoriteTagNames: { favoriteTagsLoader().map(\.name) },
            favoriteTags: favoriteTagsLoader,
        )
    }

    public nonisolated static var testValue: FinderFavoritesTagClient {
        FinderFavoritesTagClient(
            favoriteTagNames: { [] },
            favoriteTags: { [] },
        )
    }

    public nonisolated static var previewValue: FinderFavoritesTagClient { testValue }
}

extension DependencyValues {
    nonisolated var finderFavoritesTagClient: FinderFavoritesTagClient {
        get { self[FinderFavoritesTagClient.self] }
        set { self[FinderFavoritesTagClient.self] = newValue }
    }
}
