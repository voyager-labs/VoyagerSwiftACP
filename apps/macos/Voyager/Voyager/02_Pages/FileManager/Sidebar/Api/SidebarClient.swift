// swiftlint:disable file_length
import AppKit
import ComposableArchitecture
import CoreServices
import Foundation
import SwiftUI

@preconcurrency import ObjectiveC

struct SidebarClient: Sendable {
    var computerName: @Sendable () -> String
    var loadRecentItems: @Sendable (Bool, EntryClient, WorkspaceClient) async -> [Entry]
    var loadFilesWithTag: @Sendable (String, Bool, EntryClient, WorkspaceClient) async -> [Entry]
    var loadLocations: @Sendable (EntryClient) async -> [SidebarUtils.LocationItem]
    var loadFavorites: @Sendable (EntryClient, UserDefaultsClient) async -> [SidebarUtils.FavoriteItem]
    var saveFavorites: @Sendable ([SidebarUtils.FavoriteItem], UserDefaultsClient) -> Void
    var initializeDefaultFavorites: @Sendable (EntryClient) async -> [SidebarUtils.FavoriteItem]
    var iconNameForURL: @Sendable (URL, Bool, EntryClient) -> String
    var loadTags: @Sendable () async -> [SidebarUtils.TagItem]

    nonisolated init(
        computerName: @escaping @Sendable () -> String,
        loadRecentItems: @escaping @Sendable (Bool, EntryClient, WorkspaceClient) async -> [Entry],
        loadFilesWithTag: @escaping @Sendable (String, Bool, EntryClient, WorkspaceClient) async -> [Entry],
        loadLocations: @escaping @Sendable (EntryClient) async -> [SidebarUtils.LocationItem],
        loadFavorites: @escaping @Sendable (EntryClient, UserDefaultsClient) async -> [SidebarUtils.FavoriteItem],
        saveFavorites: @escaping @Sendable ([SidebarUtils.FavoriteItem], UserDefaultsClient) -> Void,
        initializeDefaultFavorites: @escaping @Sendable (EntryClient) async -> [SidebarUtils.FavoriteItem],
        iconNameForURL: @escaping @Sendable (URL, Bool, EntryClient) -> String,
        loadTags: @escaping @Sendable () async -> [SidebarUtils.TagItem],
    ) {
        self.computerName = computerName
        self.loadRecentItems = loadRecentItems
        self.loadFilesWithTag = loadFilesWithTag
        self.loadLocations = loadLocations
        self.loadFavorites = loadFavorites
        self.saveFavorites = saveFavorites
        self.initializeDefaultFavorites = initializeDefaultFavorites
        self.iconNameForURL = iconNameForURL
        self.loadTags = loadTags
    }
}

private final class CompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _hasCompleted = false

    nonisolated func setCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _hasCompleted {
            return false
        }
        _hasCompleted = true
        return true
    }
}

private final class QueryWrapper: @unchecked Sendable {
    nonisolated(unsafe) let query: NSMetadataQuery
    init(_ query: NSMetadataQuery) {
        self.query = query
    }
}

private final class ObserverWrapper: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _observer: NSObjectProtocol?

    init(_ observer: NSObjectProtocol?) {
        _observer = observer
    }

    nonisolated func setObserver(_ observer: NSObjectProtocol?) {
        lock.lock()
        defer { lock.unlock() }
        if let oldObserver = _observer {
            NotificationCenter.default.removeObserver(oldObserver)
        }
        _observer = observer
    }

    nonisolated func remove() {
        lock.lock()
        defer { lock.unlock() }
        if let observer = _observer {
            NotificationCenter.default.removeObserver(observer)
            _observer = nil
        }
    }
}

extension SidebarClient: DependencyKey {
    @MainActor
    private static func searchFiles(
        predicate: NSPredicate,
        entryClient: EntryClient,
        sortDescriptors: [NSSortDescriptor] = [],
        timeout: TimeInterval = 5,
        filterFiles: Bool = false,
    ) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let query = NSMetadataQuery()
                query.searchScopes = []
                query.predicate = predicate
                query.sortDescriptors = sortDescriptors

                let completionState = CompletionState()
                let queryWrapper = QueryWrapper(query)
                let observerWrapper = ObserverWrapper(nil)

                let observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: queryWrapper.query,
                    queue: .main,
                ) { _ in
                    let capturedQuery = queryWrapper.query
                    Task { @MainActor in
                        guard completionState.setCompleted() else { return }
                        capturedQuery.stop()

                        let urls: [URL] = Array(capturedQuery.results
                            .compactMap { $0 as? NSMetadataItem }
                            .compactMap { item -> URL? in
                                guard let path = item.value(forAttribute: "kMDItemPath") as? String
                                else { return nil }

                                if filterFiles {
                                    var isDirectory: ObjCBool = false
                                    if entryClient.fileExistsAtPath(path, &isDirectory) {
                                        if isDirectory.boolValue { return nil }
                                    }
                                }

                                return URL(fileURLWithPath: path)
                            }
                            .prefix(100))

                        continuation.resume(returning: urls)

                        observerWrapper.remove()
                    }
                }

                observerWrapper.setObserver(observer)

                query.start()

                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    let capturedQuery = queryWrapper.query
                    Task { @MainActor in
                        guard completionState.setCompleted() else { return }
                        capturedQuery.stop()
                        continuation.resume(returning: [])

                        observerWrapper.remove()
                    }
                }
            }
        }
    }

    @MainActor
    private static func loadRecentItems(showHidden: Bool, entryClient: EntryClient, workspaceClient: WorkspaceClient)
        async -> [Entry]
    {
        let predicate = NSPredicate(format: "kMDItemLastUsedDate > %@", Date.distantPast as NSDate)
        let sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        let recentFiles = await searchFiles(
            predicate: predicate,
            entryClient: entryClient,
            sortDescriptors: sortDescriptors,
            filterFiles: true,
        )

        let items = recentFiles.compactMap { url in
            EntryLoadUtils.convertURLToEntry(
                url,
                entryClient: entryClient,
                workspaceClient: workspaceClient,
            )
        }
        return showHidden ? items : items.filter { !$0.isHidden }
    }

    @MainActor
    private static func loadFilesWithTag(
        _ tag: String,
        showHidden: Bool,
        entryClient: EntryClient,
        workspaceClient: WorkspaceClient,
    ) async -> [Entry] {
        let predicate = NSPredicate(format: "kMDItemUserTags CONTAINS %@", tag)
        let sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        let taggedFiles = await searchFiles(
            predicate: predicate,
            entryClient: entryClient,
            sortDescriptors: sortDescriptors,
        )

        let items: [Entry] = taggedFiles.compactMap { url in
            guard let item = EntryLoadUtils.convertURLToEntry(
                url,
                entryClient: entryClient,
                workspaceClient: workspaceClient,
            ) else { return nil }

            let hasTags = item.tags?.contains(where: { $0.name == tag }) ?? false
            return hasTags ? item : nil
        }
        return showHidden ? items : items.filter { !$0.isHidden }
    }

    nonisolated static var liveValue: SidebarClient {
        nonisolated(unsafe) let fileManager = FileManager.default
        return SidebarClient(
            computerName: {
                fileManager.displayName(atPath: "/")
            },
            loadRecentItems: { showHidden, entryClient, workspaceClient in
                await Self.loadRecentItems(
                    showHidden: showHidden,
                    entryClient: entryClient,
                    workspaceClient: workspaceClient,
                )
            },
            loadFilesWithTag: { tagName, showHidden, entryClient, workspaceClient in
                await Self.loadFilesWithTag(
                    tagName,
                    showHidden: showHidden,
                    entryClient: entryClient,
                    workspaceClient: workspaceClient,
                )
            },
            loadLocations: { entryClient in
                await MainActor.run {
                    var locations: [SidebarUtils.LocationItem] = []

                    // Load external volumes
                    if let mountedVolumes = entryClient.mountedVolumeURLs(
                        [.volumeIsRemovableKey, .volumeIsEjectableKey],
                        [],
                    ) {
                        for volumeURL in mountedVolumes {
                            let volumeName = volumeURL.lastPathComponent
                            let resourceValues = try? volumeURL.resourceValues(forKeys: [
                                .volumeIsRemovableKey,
                                .volumeIsEjectableKey,
                            ])

                            let isRemovable = resourceValues?.volumeIsRemovable ?? false
                            let isEjectable = resourceValues?.volumeIsEjectable ?? false

                            let systemPrefixes = [
                                "com.apple",
                                "VM",
                                "Preboot",
                                "Update",
                                "xarts",
                                "iSCPreboot",
                                "Hardware",
                                "mnt",
                            ]
                            let simulatorPrefixes = ["SimRuntimeBundle-", "iOS_", "watchOS_", "tvOS_", "xrOS_"]
                            let isSystemMount = systemPrefixes
                                .contains { volumeName.hasPrefix($0) } || volumeName == "/" || volumeName == "home"
                            let isSimulatorMount = simulatorPrefixes.contains { volumeName.hasPrefix($0) }

                            if isRemovable || isEjectable, !isSystemMount, !isSimulatorMount {
                                locations.append(SidebarUtils.LocationItem(
                                    name: volumeName,
                                    url: volumeURL,
                                    iconName: "externaldrive",
                                ))
                            }
                        }
                    }

                    // Add iCloud Drive
                    let iCloudDrivePath = (NSHomeDirectory() as NSString)
                        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
                    if entryClient.fileExists(iCloudDrivePath) {
                        locations.append(SidebarUtils.LocationItem(
                            name: "iCloud Drive",
                            url: URL(fileURLWithPath: iCloudDrivePath),
                            iconName: "icloud",
                        ))
                    }

                    // Add Cloud Storage folders
                    let cloudStoragePath = (NSHomeDirectory() as NSString)
                        .appendingPathComponent("Library/CloudStorage")
                    let cloudStorageURL = URL(fileURLWithPath: cloudStoragePath)
                    if let cloudStorageContents = try? entryClient.contentsOfDirectory(
                        cloudStorageURL,
                        [.isDirectoryKey],
                        [.skipsHiddenFiles],
                    ) {
                        for itemURL in cloudStorageContents {
                            if let isDirectory = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                               isDirectory == true
                            {
                                locations.append(SidebarUtils.LocationItem(
                                    name: itemURL.lastPathComponent,
                                    url: itemURL,
                                    iconName: "folder",
                                ))
                            }
                        }
                    }

                    // Add system locations
                    let homeURL = URL(fileURLWithPath: NSHomeDirectory())
                    locations.append(SidebarUtils.LocationItem(
                        name: NSUserName(),
                        url: homeURL,
                        iconName: "house",
                    ))

                    locations.append(SidebarUtils.LocationItem(
                        name: entryClient.displayName("/"),
                        url: URL(fileURLWithPath: "/"),
                        iconName: "internaldrive",
                    ))

                    if let trashURL = entryClient.urlsForDirectory(.trashDirectory, .userDomainMask).first {
                        locations.append(SidebarUtils.LocationItem(
                            name: "Trash",
                            url: trashURL,
                            iconName: "trash",
                        ))
                    }

                    return locations
                }
            },
            loadFavorites: { entryClient, userDefaultsClient in
                let defaultFavorites = await Self.initializeDefaultFavoritesImpl(entryClient: entryClient)
                return await MainActor.run {
                    if let data = userDefaultsClient.object("favorites") as? Data,
                       let favorites = try? JSONDecoder().decode([SidebarUtils.FavoriteItem].self, from: data),
                       !favorites.isEmpty
                    {
                        let updatedFavorites = favorites.map { favorite in
                            if favorite.url.path == "/Applications" {
                                return SidebarUtils.FavoriteItem(
                                    name: favorite.name,
                                    url: favorite.url,
                                    iconName: "appstore",
                                )
                            }
                            return favorite
                        }
                        if updatedFavorites != favorites {
                            let encoded = try? JSONEncoder().encode(updatedFavorites)
                            userDefaultsClient.setObject(encoded, "favorites")
                        }
                        return updatedFavorites
                    }

                    let encoded = try? JSONEncoder().encode(defaultFavorites)
                    userDefaultsClient.setObject(encoded, "favorites")
                    return defaultFavorites
                }
            },
            saveFavorites: { favorites, userDefaultsClient in
                if let encoded = try? JSONEncoder().encode(favorites) {
                    userDefaultsClient.setObject(encoded, "favorites")
                }
            },
            initializeDefaultFavorites: { entryClient in
                await MainActor.run {
                    func makeFavorite(
                        name: String,
                        directory: FileManager.SearchPathDirectory,
                        iconName: String,
                        entryClient: EntryClient,
                        domain: FileManager.SearchPathDomainMask = .userDomainMask,
                    ) -> SidebarUtils.FavoriteItem? {
                        guard let url = entryClient.urlsForDirectory(directory, domain).first else { return nil }
                        return SidebarUtils.FavoriteItem(name: name, url: url, iconName: iconName)
                    }

                    return [
                        makeFavorite(
                            name: "Applications",
                            directory: .applicationDirectory,
                            iconName: "appstore",
                            entryClient: entryClient,
                            domain: .localDomainMask,
                        ),
                        makeFavorite(
                            name: "Desktop",
                            directory: .desktopDirectory,
                            iconName: "menubar.dock.rectangle",
                            entryClient: entryClient,
                        ),
                        makeFavorite(
                            name: "Documents",
                            directory: .documentDirectory,
                            iconName: "doc",
                            entryClient: entryClient,
                        ),
                        makeFavorite(
                            name: "Downloads",
                            directory: .downloadsDirectory,
                            iconName: "arrow.down.circle",
                            entryClient: entryClient,
                        ),
                    ].compactMap(\.self)
                }
            },
            iconNameForURL: { url, isDirectory, entryClient in
                guard isDirectory else { return "doc" }

                let path = url.path

                if path == NSHomeDirectory() { return "house" }

                if path.hasPrefix("/Volumes/") { return "externaldrive" }

                let mappings: [SidebarIconMap] = [
                    SidebarIconMap(
                        directory: .applicationDirectory,
                        domain: .localDomainMask,
                        iconName: "folder.badge.gearshape",
                    ),
                    SidebarIconMap(
                        directory: .desktopDirectory,
                        domain: .userDomainMask,
                        iconName: "menubar.dock.rectangle",
                    ),
                    SidebarIconMap(
                        directory: .documentDirectory,
                        domain: .userDomainMask,
                        iconName: "doc.text",
                    ),
                    SidebarIconMap(
                        directory: .downloadsDirectory,
                        domain: .userDomainMask,
                        iconName: "arrow.down.circle",
                    ),
                    SidebarIconMap(directory: .moviesDirectory, domain: .userDomainMask, iconName: "film"),
                    SidebarIconMap(directory: .musicDirectory, domain: .userDomainMask, iconName: "music.note"),
                    SidebarIconMap(directory: .picturesDirectory, domain: .userDomainMask, iconName: "photo"),
                    SidebarIconMap(directory: .trashDirectory, domain: .userDomainMask, iconName: "trash"),
                ]

                for mapping in mappings
                    where entryClient.urlsForDirectory(mapping.directory, mapping.domain).first?.path == path
                {
                    return mapping.iconName
                }

                return "folder"
            },
            loadTags: {
                await MainActor.run {
                    let tagNames = EntryTagUtils.getFavoriteTagNames()
                    let nameToColorCode = EntryTagUtils.getTagNameToColorCodeMapping()

                    return tagNames
                        .filter { !$0.isEmpty }
                        .map { name in
                            let colorCode = nameToColorCode[name] ?? 0
                            return SidebarUtils.TagItem(
                                name: name,
                                color: EntryTagUtils.getTagColor(colorCode: colorCode),
                            )
                        }
                        .sorted { tag1, tag2 in
                            let colorCode1 = nameToColorCode[tag1.name] ?? 0
                            let colorCode2 = nameToColorCode[tag2.name] ?? 0

                            let idx1 = EntryTagUtils.colorCodeOrder.firstIndex(of: colorCode1) ?? 999
                            let idx2 = EntryTagUtils.colorCodeOrder.firstIndex(of: colorCode2) ?? 999
                            return idx1 < idx2
                        }
                }
            },
        )
    }

    private static func initializeDefaultFavoritesImpl(entryClient: EntryClient) async -> [SidebarUtils.FavoriteItem] {
        await MainActor.run {
            func makeFavorite(
                name: String,
                directory: FileManager.SearchPathDirectory,
                iconName: String,
                entryClient: EntryClient,
                domain: FileManager.SearchPathDomainMask = .userDomainMask,
            ) -> SidebarUtils.FavoriteItem? {
                guard let url = entryClient.urlsForDirectory(directory, domain).first else { return nil }
                return SidebarUtils.FavoriteItem(name: name, url: url, iconName: iconName)
            }

            return [
                makeFavorite(
                    name: "Applications",
                    directory: .applicationDirectory,
                    iconName: "appstore",
                    entryClient: entryClient,
                    domain: .localDomainMask,
                ),
                makeFavorite(
                    name: "Desktop",
                    directory: .desktopDirectory,
                    iconName: "menubar.dock.rectangle",
                    entryClient: entryClient,
                ),
                makeFavorite(
                    name: "Documents",
                    directory: .documentDirectory,
                    iconName: "doc",
                    entryClient: entryClient,
                ),
                makeFavorite(
                    name: "Downloads",
                    directory: .downloadsDirectory,
                    iconName: "arrow.down.circle",
                    entryClient: entryClient,
                ),
            ].compactMap(\.self)
        }
    }

    nonisolated static var testValue: SidebarClient {
        SidebarClient(
            computerName: { "" },
            loadRecentItems: { _, _, _ in [] },
            loadFilesWithTag: { _, _, _, _ in [] },
            loadLocations: { _ in [] },
            loadFavorites: { _, _ in [] },
            saveFavorites: { _, _ in },
            initializeDefaultFavorites: { _ async in [] },
            iconNameForURL: { _, _, _ in "folder" },
            loadTags: { [] },
        )
    }

    nonisolated static var previewValue: SidebarClient {
        SidebarClient(
            computerName: { "" },
            loadRecentItems: { _, _, _ in [] },
            loadFilesWithTag: { _, _, _, _ in [] },
            loadLocations: { _ in [] },
            loadFavorites: { _, _ in [] },
            saveFavorites: { _, _ in },
            initializeDefaultFavorites: { _ async in [] },
            iconNameForURL: { _, _, _ in "folder" },
            loadTags: { [] },
        )
    }
}

extension DependencyValues {
    nonisolated var sidebarClient: SidebarClient {
        get { self[SidebarClient.self] }
        set { self[SidebarClient.self] = newValue }
    }
}

// swiftlint:enable file_length
