import AppKit
import CoreServices
import Foundation
import SwiftUI

@preconcurrency import ObjectiveC

// swiftlint:disable type_body_length
enum SidebarUtils {
    struct LocationItem: Equatable {
        let name: String
        let url: URL
        let iconName: String

        var isComputer: Bool {
            url.scheme == "computer"
        }
    }

    static var computerName: String {
        FileManager.default.displayName(atPath: "/")
    }

    static var iCloudDrivePath: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }

    static var cloudStoragePath: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/CloudStorage")
    }

    struct TagItem: Equatable {
        let name: String
        let color: Color
    }

    struct FavoriteItem: Equatable, Codable {
        let name: String
        let url: URL
        let iconName: String

        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case name
            case url
            case iconName
        }

        init(name: String, url: URL, iconName: String) {
            self.name = name
            self.url = url
            self.iconName = iconName
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            let urlString = try container.decode(String.self, forKey: .url)
            guard let decodedURL = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .url,
                    in: container,
                    debugDescription: "Invalid URL string",
                )
            }
            url = decodedURL
            iconName = try container.decode(String.self, forKey: .iconName)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(url.absoluteString, forKey: .url)
            try container.encode(iconName, forKey: .iconName)
        }

        var displayName: String {
            SidebarUtils.favoriteDisplayName(for: self)
        }
    }

    @MainActor
    static func saveFavorites(_ favorites: [FavoriteItem]) {
        if let encoded = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encoded, forKey: "favorites")
        }
    }

    static func iconNameForURL(_ url: URL, isDirectory: Bool) -> String {
        guard isDirectory else { return "doc" }

        let path = url.path

        if path == NSHomeDirectory() { return "house" }

        if path.hasPrefix("/Volumes/") { return "externaldrive" }

        let fm = FileManager.default
        // swiftlint:disable:next large_tuple
        let mappings: [(FileManager.SearchPathDirectory, FileManager.SearchPathDomainMask, String)] = [
            (.applicationDirectory, .localDomainMask, "folder.badge.gearshape"),
            (.desktopDirectory, .userDomainMask, "desktopcomputer"),
            (.documentDirectory, .userDomainMask, "doc.text"),
            (.downloadsDirectory, .userDomainMask, "arrow.down.circle"),
            (.moviesDirectory, .userDomainMask, "film"),
            (.musicDirectory, .userDomainMask, "music.note"),
            (.picturesDirectory, .userDomainMask, "photo"),
            (.trashDirectory, .userDomainMask, "trash"),
        ]

        for (dir, domain, icon) in mappings where fm.urls(for: dir, in: domain).first?.path == path {
            return icon
        }

        return "folder"
    }

    static func favoriteDisplayName(for favorite: FavoriteItem) -> String {
        if favorite.url.pathExtension.lowercased() == "voycoll" {
            return favorite.url.deletingPathExtension().lastPathComponent
        }
        return favorite.name
    }

    @MainActor
    static func initializeDefaultFavorites() -> [FavoriteItem] {
        func makeFavorite(
            name: String,
            directory: FileManager.SearchPathDirectory,
            iconName: String,
            domain: FileManager.SearchPathDomainMask = .userDomainMask,
        ) -> FavoriteItem? {
            guard let url = FileManager.default.urls(for: directory, in: domain).first else { return nil }
            return FavoriteItem(name: name, url: url, iconName: iconName)
        }

        return [
            makeFavorite(
                name: "Applications",
                directory: .applicationDirectory,
                iconName: "appstore",
                domain: .localDomainMask,
            ),
            makeFavorite(name: "Desktop", directory: .desktopDirectory, iconName: "desktopcomputer"),
            makeFavorite(name: "Documents", directory: .documentDirectory, iconName: "doc"),
            makeFavorite(name: "Downloads", directory: .downloadsDirectory, iconName: "arrow.down.circle"),
        ].compactMap(\.self)
    }

    @MainActor
    static func loadFavorites() -> [FavoriteItem] {
        if let data = UserDefaults.standard.data(forKey: "favorites"),
           let favorites = try? JSONDecoder().decode([FavoriteItem].self, from: data),
           !favorites.isEmpty
        {
            let updatedFavorites = favorites.map { favorite in
                if favorite.url.path == "/Applications" {
                    return FavoriteItem(
                        name: favorite.name,
                        url: favorite.url,
                        iconName: "appstore",
                    )
                }
                return favorite
            }
            if updatedFavorites != favorites {
                saveFavorites(updatedFavorites)
            }
            return updatedFavorites
        }

        let defaultFavorites = initializeDefaultFavorites()
        saveFavorites(defaultFavorites)
        return defaultFavorites
    }

    @MainActor
    private static func loadExternalVolumes() -> [LocationItem] {
        var volumes: [LocationItem] = []

        guard let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey],
            options: [],
        ) else {
            return volumes
        }

        for volumeURL in mountedVolumes {
            let volumeName = volumeURL.lastPathComponent
            let resourceValues = try? volumeURL.resourceValues(forKeys: [
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
            ])

            let isRemovable = resourceValues?.volumeIsRemovable ?? false
            let isEjectable = resourceValues?.volumeIsEjectable ?? false

            let systemPrefixes = ["com.apple", "VM", "Preboot", "Update", "xarts", "iSCPreboot", "Hardware", "mnt"]
            let simulatorPrefixes = ["SimRuntimeBundle-", "iOS_", "watchOS_", "tvOS_", "xrOS_"]
            let isSystemMount = systemPrefixes
                .contains { volumeName.hasPrefix($0) } || volumeName == "/" || volumeName == "home"
            let isSimulatorMount = simulatorPrefixes.contains { volumeName.hasPrefix($0) }

            if isRemovable || isEjectable, !isSystemMount, !isSimulatorMount {
                volumes.append(LocationItem(
                    name: volumeName,
                    url: volumeURL,
                    iconName: "externaldrive",
                ))
            }
        }

        return volumes
    }

    @MainActor
    private static func addiCloudDrive(to locations: inout [LocationItem]) {
        let iCloudDriveURL = URL(fileURLWithPath: iCloudDrivePath)
        if FileManager.default.fileExists(atPath: iCloudDrivePath) {
            locations.append(LocationItem(
                name: "iCloud Drive",
                url: iCloudDriveURL,
                iconName: "icloud",
            ))
        }
    }

    @MainActor
    private static func addCloudStorageFolders(to locations: inout [LocationItem]) {
        let cloudStorageURL = URL(fileURLWithPath: cloudStoragePath)
        guard let cloudStorageContents = try? FileManager.default.contentsOfDirectory(
            at: cloudStorageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        ) else {
            return
        }

        for itemURL in cloudStorageContents {
            if let isDirectory = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
               isDirectory == true
            {
                locations.append(LocationItem(
                    name: itemURL.lastPathComponent,
                    url: itemURL,
                    iconName: "folder",
                ))
            }
        }
    }

    @MainActor
    private static func addSystemLocations(to locations: inout [LocationItem]) {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())

        locations.append(LocationItem(
            name: NSUserName(),
            url: homeURL,
            iconName: "house",
        ))

        locations.append(LocationItem(
            name: computerName,
            url: URL(fileURLWithPath: "/"),
            iconName: "internaldrive",
        ))

        if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
            locations.append(LocationItem(
                name: "Trash",
                url: trashURL,
                iconName: "trash",
            ))
        }
    }

    @MainActor
    static func loadLocations() -> [LocationItem] {
        var locations: [LocationItem] = []

        locations.append(contentsOf: loadExternalVolumes())
        addiCloudDrive(to: &locations)
        addCloudStorageFolders(to: &locations)
        addSystemLocations(to: &locations)

        return locations
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

    @MainActor
    private static func searchFiles(
        predicate: NSPredicate,
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
                                    if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
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
    static func loadTags() async -> [TagItem] {
        let tagNames = EntryTagUtils.getFavoriteTagNames()
        let nameToColorCode = EntryTagUtils.getTagNameToColorCodeMapping()

        return tagNames
            .filter { !$0.isEmpty }
            .map { name in
                let colorCode = nameToColorCode[name] ?? 0
                return TagItem(
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

    @MainActor
    static func loadRecentItems(showHidden: Bool) async -> [Entry] {
        let predicate = NSPredicate(format: "kMDItemLastUsedDate > %@", Date.distantPast as NSDate)
        let sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        let recentFiles = await searchFiles(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            filterFiles: true,
        )

        let items = recentFiles.compactMap { EntryLoadUtils.convertURLToEntry($0) }
        return showHidden ? items : items.filter { !$0.isHidden }
    }

    @MainActor
    static func loadFilesWithTag(_ tag: String, showHidden: Bool) async -> [Entry] {
        let predicate = NSPredicate(format: "kMDItemUserTags CONTAINS %@", tag)
        let sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        let taggedFiles = await searchFiles(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
        )

        let items: [Entry] = taggedFiles.compactMap { url in
            guard let item = EntryLoadUtils.convertURLToEntry(url) else { return nil }

            let hasTags = item.tags?.contains(where: { $0.name == tag }) ?? false
            return hasTags ? item : nil
        }
        return showHidden ? items : items.filter { !$0.isHidden }
    }
}

// swiftlint:enable type_body_length
