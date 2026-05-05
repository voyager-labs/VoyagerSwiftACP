import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

struct FileManagerIconClient: Sendable {
    var iconNameForURL: @Sendable (URL, Bool, EntryLoadingClient) -> String

    nonisolated init(
        iconNameForURL: @escaping @Sendable (URL, Bool, EntryLoadingClient) -> String,
    ) {
        self.iconNameForURL = iconNameForURL
    }
}

extension FileManagerIconClient: DependencyKey {
    private typealias IconLocation = (
        directory: FileManager.SearchPathDirectory,
        domain: FileManager.SearchPathDomainMask,
    )

    private nonisolated(unsafe) static let iconMappings: [(location: IconLocation, iconName: String)] = [
        (
            location: (
                directory: .applicationDirectory,
                domain: .localDomainMask,
            ),
            iconName: "folder.badge.gearshape",
        ),
        (
            location: (
                directory: .desktopDirectory,
                domain: .userDomainMask,
            ),
            iconName: "menubar.dock.rectangle",
        ),
        (
            location: (
                directory: .documentDirectory,
                domain: .userDomainMask,
            ),
            iconName: "doc.text",
        ),
        (
            location: (
                directory: .downloadsDirectory,
                domain: .userDomainMask,
            ),
            iconName: "arrow.down.circle",
        ),
        (location: (directory: .moviesDirectory, domain: .userDomainMask), iconName: "film"),
        (location: (directory: .musicDirectory, domain: .userDomainMask), iconName: "music.note"),
        (location: (directory: .picturesDirectory, domain: .userDomainMask), iconName: "photo"),
        (location: (directory: .trashDirectory, domain: .userDomainMask), iconName: "trash"),
    ]

    nonisolated static func resolveIconName(
        for url: URL,
        isDirectory: Bool,
        entryLoadingClient: EntryLoadingClient,
    ) -> String {
        guard isDirectory else { return "doc" }

        let path = url.path

        if path == NSHomeDirectory() { return "house" }

        if path.hasPrefix("/Volumes/") { return "externaldrive" }

        for mapping in Self.iconMappings
            where entryLoadingClient.urlsForDirectory(
                mapping.location.directory,
                mapping.location.domain,
            ).first?.path == path
        {
            return mapping.iconName
        }

        return "folder"
    }

    nonisolated static var liveValue: FileManagerIconClient {
        FileManagerIconClient(
            iconNameForURL: { url, isDirectory, entryLoadingClient in
                resolveIconName(for: url, isDirectory: isDirectory, entryLoadingClient: entryLoadingClient)
            },
        )
    }

    nonisolated static var testValue: FileManagerIconClient {
        FileManagerIconClient(
            iconNameForURL: { _, _, _ in "folder" },
        )
    }

    nonisolated static var previewValue: FileManagerIconClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var fileManagerIconClient: FileManagerIconClient {
        get { self[FileManagerIconClient.self] }
        set { self[FileManagerIconClient.self] = newValue }
    }
}
