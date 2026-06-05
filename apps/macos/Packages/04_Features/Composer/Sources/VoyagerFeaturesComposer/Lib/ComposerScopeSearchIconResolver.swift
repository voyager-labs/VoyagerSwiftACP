import Foundation
import VoyagerEntitiesEntry

enum ComposerScopeSearchIconResolver {
    private struct IconMapping {
        let directory: FileManager.SearchPathDirectory
        let domain: FileManager.SearchPathDomainMask
        let iconName: String
    }

    nonisolated static func buildPathMapping(
        entryLoadingClient: EntryLoadingClient,
    ) -> [String: String] {
        let mappings: [IconMapping] = [
            IconMapping(directory: .applicationDirectory, domain: .localDomainMask, iconName: "folder.badge.gearshape"),
            IconMapping(directory: .desktopDirectory, domain: .userDomainMask, iconName: "menubar.dock.rectangle"),
            IconMapping(directory: .documentDirectory, domain: .userDomainMask, iconName: "doc.text"),
            IconMapping(directory: .downloadsDirectory, domain: .userDomainMask, iconName: "arrow.down.circle"),
            IconMapping(directory: .moviesDirectory, domain: .userDomainMask, iconName: "film"),
            IconMapping(directory: .musicDirectory, domain: .userDomainMask, iconName: "music.note"),
            IconMapping(directory: .picturesDirectory, domain: .userDomainMask, iconName: "photo"),
            IconMapping(directory: .trashDirectory, domain: .userDomainMask, iconName: "trash"),
        ]

        var pathMap: [String: String] = [:]
        for mapping in mappings {
            if let path = entryLoadingClient.urlsForDirectory(mapping.directory, mapping.domain).first?.path {
                pathMap[path] = mapping.iconName
            }
        }

        return pathMap
    }

    nonisolated static func iconName(
        for path: String,
        homePath: String,
        iconPathMap: [String: String],
    ) -> String {
        if path == homePath { return "house" }
        if path.hasPrefix("/Volumes/") { return "externaldrive" }
        if let mapped = iconPathMap[path] { return mapped }

        return "folder"
    }
}
