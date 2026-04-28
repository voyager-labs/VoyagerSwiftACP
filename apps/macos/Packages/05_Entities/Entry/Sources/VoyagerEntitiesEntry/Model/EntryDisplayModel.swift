import Foundation

public struct EntryDisplayModel: Sendable {
    public let entry: EntryModel

    public init(entry: EntryModel) {
        self.entry = entry
    }

    public var formattedSize: String {
        guard !entry.isFolder else { return "--" }
        return EntryDisplayFormatting.byteFormatter.string(fromByteCount: entry.size)
    }

    public var formattedModifiedDate: String {
        EntryDisplayFormatting.dateFormatter.string(from: entry.modifiedDate)
    }

    public var formattedCreatedDate: String {
        EntryDisplayFormatting.dateFormatter.string(from: entry.facets.createdDate)
    }

    public var supplementaryInfoText: String? {
        guard let metadata = entry.facets.supplementaryMetadata else { return nil }

        switch metadata {
        case let .folderItemCount(count):
            if count == 0 {
                return "No items"
            }
            return "\(count) item\(count == 1 ? "" : "s")"
        case let .imageResolution(width, height):
            return "\(width) × \(height)"
        case let .compressedFileSize(bytes):
            return EntryDisplayFormatting.archiveSizeFormatter.string(fromByteCount: bytes)
        }
    }
}

private enum EntryDisplayFormatting {
    nonisolated static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    nonisolated(unsafe) static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    nonisolated(unsafe) static let archiveSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}
