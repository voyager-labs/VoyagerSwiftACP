import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

public struct FileManagerLocationsClient: Sendable {
    public var loadLocations: @Sendable (EntryLoadingClient) -> [SidebarItems.LocationItem]

    nonisolated public init(
        loadLocations: @escaping @Sendable (EntryLoadingClient) -> [SidebarItems.LocationItem],
    ) {
        self.loadLocations = loadLocations
    }
}

extension FileManagerLocationsClient: DependencyKey {
    nonisolated public static var liveValue: FileManagerLocationsClient {
        FileManagerLocationsClient(
            loadLocations: { entryLoadingClient in
                var locations: [SidebarItems.LocationItem] = []

                locations.append(contentsOf: removableVolumes(entryLoadingClient: entryLoadingClient))

                let iCloudDrivePath = (entryLoadingClient.homeDirectory() as NSString)
                    .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
                if entryLoadingClient.fileExists(iCloudDrivePath) {
                    locations.append(SidebarItems.LocationItem(
                        name: "iCloud Drive",
                        url: URL(fileURLWithPath: iCloudDrivePath),
                        iconName: "icloud",
                    ))
                }

                let cloudStoragePath = (entryLoadingClient.homeDirectory() as NSString)
                    .appendingPathComponent("Library/CloudStorage")
                let cloudStorageURL = URL(fileURLWithPath: cloudStoragePath)
                if let cloudStorageContents = try? entryLoadingClient.contentsOfDirectory(
                    cloudStorageURL,
                    [.isDirectoryKey],
                    [.skipsHiddenFiles],
                ) {
                    for itemURL in cloudStorageContents {
                        if let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
                           isDirectory == true
                        {
                            locations.append(SidebarItems.LocationItem(
                                name: itemURL.lastPathComponent,
                                url: itemURL,
                                iconName: "folder",
                            ))
                        }
                    }
                }

                let homePath = entryLoadingClient.homeDirectory()
                locations.append(SidebarItems.LocationItem(
                    name: (homePath as NSString).lastPathComponent,
                    url: URL(fileURLWithPath: homePath),
                    iconName: "house",
                ))

                locations.append(SidebarItems.LocationItem(
                    name: entryLoadingClient.displayName("/"),
                    url: URL(fileURLWithPath: "/"),
                    iconName: "internaldrive",
                ))

                if let trashURL = entryLoadingClient.urlsForDirectory(.trashDirectory, .userDomainMask).first {
                    locations.append(SidebarItems.LocationItem(
                        name: "Trash",
                        url: trashURL,
                        iconName: "trash",
                    ))
                }

                return locations
            },
        )
    }

    nonisolated private static func removableVolumes(
        entryLoadingClient: EntryLoadingClient,
    ) -> [SidebarItems.LocationItem] {
        guard let mountedVolumes = entryLoadingClient.mountedVolumeURLs(
            [.volumeIsRemovableKey, .volumeIsEjectableKey],
            [],
        ) else { return [] }

        return mountedVolumes.compactMap { volumeURL in
            let volumeName = volumeURL.lastPathComponent
            let resourceValues = try? volumeURL.resourceValues(forKeys: [
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
            ])

            let isRemovable = resourceValues?.volumeIsRemovable ?? false
            let isEjectable = resourceValues?.volumeIsEjectable ?? false
            guard isRemovable || isEjectable else { return nil }

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
            let isSystemMount = systemPrefixes.contains { volumeName.hasPrefix($0) }
                || volumeName == "/"
                || volumeName == "home"
            let isSimulatorMount = simulatorPrefixes.contains { volumeName.hasPrefix($0) }
            guard !isSystemMount, !isSimulatorMount else { return nil }

            return SidebarItems.LocationItem(
                name: volumeName,
                url: volumeURL,
                iconName: "externaldrive",
            )
        }
    }

    nonisolated public static var testValue: FileManagerLocationsClient {
        FileManagerLocationsClient(loadLocations: { _ in [] })
    }

    nonisolated public static var previewValue: FileManagerLocationsClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var fileManagerLocationsClient: FileManagerLocationsClient {
        get { self[FileManagerLocationsClient.self] }
        set { self[FileManagerLocationsClient.self] = newValue }
    }
}
