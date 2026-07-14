import ComposableArchitecture
import VoyagerEntitiesCollection
import VoyagerEntitiesTag

public struct FileManagerBuiltInCollectionClient: Sendable {
    public var ensureAll: @Sendable () async -> BuiltInCollectionEnsureReport

    public init(
        ensureAll: @escaping @Sendable () async -> BuiltInCollectionEnsureReport,
    ) {
        self.ensureAll = ensureAll
    }
}

extension FileManagerBuiltInCollectionClient: DependencyKey {
    public static let liveValue = FileManagerBuiltInCollectionClient(
        ensureAll: {
            @Dependency(\.builtInCollectionClient)
            var builtInCollectionClient
            @Dependency(\.finderFavoritesTagClient)
            var finderFavoritesTagClient
            @Dependency(\.registryClient)
            var registryClient

            let tagNames = FileManagerVirtualCollectionContextFactory.normalizeTagNames(
                finderFavoritesTagClient.favoriteTagNames(),
            )
            let recentsContext = FileManagerVirtualCollectionContextFactory.recentsCollectionContext(
                registryClient: registryClient,
            )
            let allTagsContext = tagNames.isEmpty ? nil :
                FileManagerVirtualCollectionContextFactory.allTagsCollectionContext(
                    tagNames: tagNames,
                    registryClient: registryClient,
                )
            return await builtInCollectionClient.ensureAll(recentsContext, allTagsContext)
        },
    )

    public static let testValue = FileManagerBuiltInCollectionClient(
        ensureAll: { .init(recents: .failed, allTags: .failed) },
    )
}

public extension DependencyValues {
    var fileManagerBuiltInCollectionClient: FileManagerBuiltInCollectionClient {
        get { self[FileManagerBuiltInCollectionClient.self] }
        set { self[FileManagerBuiltInCollectionClient.self] = newValue }
    }
}
