import AppKit
import CoreServices
import Foundation
import SwiftUI

@preconcurrency import ObjectiveC

enum SidebarUtils {
    struct LocationItem: Equatable {
        let name: String
        let url: URL
        let iconName: String
    }

    struct TagItem: Equatable {
        let name: String
        let color: Color
    }

    struct FavoriteItem: Equatable {
        let name: String
        let url: URL
        let iconName: String
    }

    @MainActor
    static func loadFavorites() -> [FavoriteItem] {
        func makeFavorite(
            name: String,
            directory: FileManager.SearchPathDirectory,
            iconName: String,
            domain: FileManager.SearchPathDomainMask = .userDomainMask
        ) -> FavoriteItem? {
            guard let url = FileManager.default.urls(for: directory, in: domain).first else { return nil }
            return FavoriteItem(name: name, url: url, iconName: iconName)
        }

        return [
            makeFavorite(
                name: "Applications",
                directory: .applicationDirectory,
                iconName: "folder",
                domain: .localDomainMask
            ),
            makeFavorite(name: "Desktop", directory: .desktopDirectory, iconName: "desktopcomputer"),
            makeFavorite(name: "Documents", directory: .documentDirectory, iconName: "doc"),
            makeFavorite(name: "Downloads", directory: .downloadsDirectory, iconName: "arrow.down.circle"),
        ].compactMap { $0 }
    }

    @MainActor
    static func loadLocations() -> [LocationItem] {
        var locations: [LocationItem] = []

        let homeURL = URL(fileURLWithPath: NSHomeDirectory())

        locations.append(LocationItem(
            name: NSUserName(),
            url: homeURL,
            iconName: "house"
        ))

        if let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey],
            options: []
        ) {
            for volumeURL in mountedVolumes {
                let volumeName = volumeURL.lastPathComponent
                let resourceValues = try? volumeURL.resourceValues(forKeys: [
                    .volumeIsRemovableKey,
                    .volumeIsEjectableKey,
                ])

                let isRemovable = resourceValues?.volumeIsRemovable ?? false
                let isEjectable = resourceValues?.volumeIsEjectable ?? false

                let systemPrefixes = ["com.apple", "VM", "Preboot", "Update", "xarts", "iSCPreboot", "Hardware", "mnt"]
                let isSystemMount = systemPrefixes
                    .contains { volumeName.hasPrefix($0) } || volumeName == "/" || volumeName == "home"

                if isRemovable || isEjectable, !isSystemMount {
                    locations.append(LocationItem(
                        name: volumeName,
                        url: volumeURL,
                        iconName: "externaldrive"
                    ))
                }
            }
        }

        if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
            locations.append(LocationItem(
                name: "Trash",
                url: trashURL,
                iconName: "trash"
            ))
        }

        return locations
    }

    @MainActor
    private static func searchFiles(
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor] = [],
        timeout: TimeInterval = 5,
        filterFiles: Bool = false
    ) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let query = NSMetadataQuery()
                query.searchScopes = []
                query.predicate = predicate
                query.sortDescriptors = sortDescriptors

                var observer: NSObjectProtocol?
                var hasCompleted = false

                observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: query,
                    queue: .main
                ) { _ in
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    query.stop()

                    let urls: [URL] = Array(query.results
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

                    if let observer = observer {
                        NotificationCenter.default.removeObserver(observer)
                    }
                }

                query.start()

                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    query.stop()
                    continuation.resume(returning: [])

                    if let observer = observer {
                        NotificationCenter.default.removeObserver(observer)
                    }
                }
            }
        }
    }

    @MainActor
    static func loadTags() async -> [TagItem] {
        let tagNames = FSItemTagUtils.getFavoriteTagNames()
        let nameToColorCode = FSItemTagUtils.getTagNameToColorCodeMapping()

        return tagNames
            .filter { !$0.isEmpty }
            .map { name in
                let colorCode = nameToColorCode[name] ?? 0
                return TagItem(
                    name: name,
                    color: FSItemTagUtils.getTagColor(colorCode: colorCode)
                )
            }
            .sorted { tag1, tag2 in
                let colorCode1 = nameToColorCode[tag1.name] ?? 0
                let colorCode2 = nameToColorCode[tag2.name] ?? 0

                let idx1 = FSItemTagUtils.colorCodeOrder.firstIndex(of: colorCode1) ?? 999
                let idx2 = FSItemTagUtils.colorCodeOrder.firstIndex(of: colorCode2) ?? 999
                return idx1 < idx2
            }
    }

    @MainActor
    static func loadRecentItems() async -> [FSItem] {
        let predicate = NSPredicate(format: "kMDItemLastUsedDate > %@", Date.distantPast as NSDate)
        let sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        let recentFiles = await searchFiles(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            filterFiles: true
        )

        return recentFiles.compactMap { FSItemLoadUtils.convertURLToFSItem($0) }
    }

    @MainActor
    static func loadFilesWithTag(_ tag: String) async -> [FSItem] {
        let predicate = NSPredicate(format: "kMDItemUserTags CONTAINS %@", tag)
        let sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        let taggedFiles = await searchFiles(
            predicate: predicate,
            sortDescriptors: sortDescriptors
        )

        return taggedFiles.compactMap { url in
            guard let item = FSItemLoadUtils.convertURLToFSItem(url) else { return nil }

            let hasTags = item.tags?.contains(where: { $0.name == tag }) ?? false
            return hasTags ? item : nil
        }
    }
}
