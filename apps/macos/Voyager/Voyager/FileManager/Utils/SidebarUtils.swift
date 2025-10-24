import AppKit
import Foundation

enum SidebarUtils {
    struct LocationItem: Equatable {
        let name: String
        let url: URL
        let iconName: String
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

        locations.append(LocationItem(
            name: "AirDrop",
            url: URL(fileURLWithPath: "/"),
            iconName: "antenna.radiowaves.left.and.right"
        ))

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
    static func loadRecentItems() async -> [FSItem] {
        let recentFiles = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let query = NSMetadataQuery()
                query.searchScopes = []
                query.predicate = NSPredicate(
                    format: "kMDItemLastUsedDate > %@",
                    Date.distantPast as NSDate
                )
                query.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

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
                            guard let path = item.value(forAttribute: kMDItemPath as String) as? String
                            else { return nil }

                            var isDirectory: ObjCBool = false
                            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                                if isDirectory.boolValue { return nil }
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

                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
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

        let recentItems = recentFiles.compactMap { FSItemsLoadUtils.convertURLToFSItem($0) }
        return recentItems
    }
}
