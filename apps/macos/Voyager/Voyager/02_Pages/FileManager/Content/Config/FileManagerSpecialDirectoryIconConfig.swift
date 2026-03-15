import Foundation

struct FileManagerSpecialDirectoryIconMapping {
    let directory: FileManager.SearchPathDirectory
    let domain: FileManager.SearchPathDomainMask
    let iconSystemName: String
}

enum FileManagerSpecialDirectoryIconConfig {
    static let specialDirectoryIconMappings: [FileManagerSpecialDirectoryIconMapping] = [
        .init(directory: .applicationDirectory, domain: .localDomainMask, iconSystemName: "folder.badge.gearshape"),
        .init(directory: .desktopDirectory, domain: .userDomainMask, iconSystemName: "menubar.dock.rectangle"),
        .init(directory: .documentDirectory, domain: .userDomainMask, iconSystemName: "doc.text"),
        .init(directory: .downloadsDirectory, domain: .userDomainMask, iconSystemName: "arrow.down.circle"),
        .init(directory: .moviesDirectory, domain: .userDomainMask, iconSystemName: "film"),
        .init(directory: .musicDirectory, domain: .userDomainMask, iconSystemName: "music.note"),
        .init(directory: .picturesDirectory, domain: .userDomainMask, iconSystemName: "photo"),
        .init(directory: .trashDirectory, domain: .userDomainMask, iconSystemName: "trash"),
    ]
}
