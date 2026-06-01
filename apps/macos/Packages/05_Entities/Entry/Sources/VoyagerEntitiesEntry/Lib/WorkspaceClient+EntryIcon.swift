import AppKit
import Foundation
import UniformTypeIdentifiers
import VoyagerShared

public extension WorkspaceClient {
    func entryIcon(for entry: EntryModel, thumbnail: NSImage?) -> NSImage {
        if let thumbnail {
            return thumbnail
        }

        return if entry.fullPath == "/" {
            iconForFile("/")
        } else if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            NSImage(named: CollectionConstants.fileIconName)
                ?? iconForType(.data)
        } else if entry.isFolder {
            iconForFile(entry.fullPath)
        } else if let utType = UTType(filenameExtension: entry.fileExtension) {
            iconForType(utType)
        } else {
            iconForType(.data)
        }
    }
}
