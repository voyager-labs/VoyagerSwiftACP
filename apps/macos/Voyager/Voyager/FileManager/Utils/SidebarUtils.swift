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
                let isSystemMount = systemPrefixes.contains { volumeName.hasPrefix($0) } || volumeName == "/" || volumeName == "home"

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
}
