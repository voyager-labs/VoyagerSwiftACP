import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

public struct FileManagerLocationsClient: Sendable {
    public var loadLocations: @Sendable (EntryLoadingClient) async -> [SidebarItems.LocationItem]

    public nonisolated init(
        loadLocations: @escaping @Sendable (EntryLoadingClient) async -> [SidebarItems.LocationItem]
    ) {
        self.loadLocations = loadLocations
    }
}

extension FileManagerLocationsClient: DependencyKey {
    public nonisolated static var liveValue: FileManagerLocationsClient {
        FileManagerLocationsClient(
            loadLocations: { entryLoadingClient in
                await MainActor.run {
                    var locations: [SidebarItems.LocationItem] = []

                    if let mountedVolumes = entryLoadingClient.mountedVolumeURLs(
                        [.volumeIsRemovableKey, .volumeIsEjectableKey],
                        []
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
                                locations.append(SidebarItems.LocationItem(
                                    name: volumeName,
                                    url: volumeURL,
                                    iconName: "externaldrive"
                                ))
                            }
                        }
                    }

                    let iCloudDrivePath = (NSHomeDirectory() as NSString)
                        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
                    if entryLoadingClient.fileExists(iCloudDrivePath) {
                        locations.append(SidebarItems.LocationItem(
                            name: "iCloud Drive",
                            url: URL(fileURLWithPath: iCloudDrivePath),
                            iconName: "icloud"
                        ))
                    }

                    let cloudStoragePath = (NSHomeDirectory() as NSString)
                        .appendingPathComponent("Library/CloudStorage")
                    let cloudStorageURL = URL(fileURLWithPath: cloudStoragePath)
                    if let cloudStorageContents = try? entryLoadingClient.contentsOfDirectory(
                        cloudStorageURL,
                        [.isDirectoryKey],
                        [.skipsHiddenFiles]
                    ) {
                        for itemURL in cloudStorageContents {
                            if let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
                               isDirectory == true
                            {
                                locations.append(SidebarItems.LocationItem(
                                    name: itemURL.lastPathComponent,
                                    url: itemURL,
                                    iconName: "folder"
                                ))
                            }
                        }
                    }

                    let homeURL = URL(fileURLWithPath: NSHomeDirectory())
                    locations.append(SidebarItems.LocationItem(
                        name: NSUserName(),
                        url: homeURL,
                        iconName: "house"
                    ))

                    locations.append(SidebarItems.LocationItem(
                        name: entryLoadingClient.displayName("/"),
                        url: URL(fileURLWithPath: "/"),
                        iconName: "internaldrive"
                    ))

                    if let trashURL = entryLoadingClient.urlsForDirectory(.trashDirectory, .userDomainMask).first {
                        locations.append(SidebarItems.LocationItem(
                            name: "Trash",
                            url: trashURL,
                            iconName: "trash"
                        ))
                    }

                    return locations
                }
            }
        )
    }

    public nonisolated static var testValue: FileManagerLocationsClient {
        FileManagerLocationsClient(
            loadLocations: { _ in [] }
        )
    }

    public nonisolated static var previewValue: FileManagerLocationsClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var fileManagerLocationsClient: FileManagerLocationsClient {
        get { self[FileManagerLocationsClient.self] }
        set { self[FileManagerLocationsClient.self] = newValue }
    }
}
