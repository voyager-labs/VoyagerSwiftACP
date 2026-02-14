import ComposableArchitecture
import Foundation
import IdentifiedCollections
import OSLog
import UniformTypeIdentifiers

enum EntryReducerSupport {
    static let entryActionLogger = Logger(subsystem: "com.voyager", category: "entry-actions")
    static let entryLoadLogger = Logger(subsystem: "com.voyager", category: "entry-load")

    static func deduplicateById(_ items: [Entry]) -> [Entry] {
        var seen: Set<String> = []
        var unique: [Entry] = []
        unique.reserveCapacity(items.count)

        for item in items where seen.insert(item.id).inserted {
            unique.append(item)
        }

        return unique
    }

    static func computerName(entryLoadingClient: EntryLoadingClient) -> String {
        entryLoadingClient.displayName("/")
    }

    static func logClientError(_ message: String) {
        entryActionLogger.info("ClientError: \(message, privacy: .public)")
    }

    static func shouldExcludeThumbnailPath(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ["app", "icon"].contains(ext) {
            return true
        }

        if let type = UTType(filenameExtension: ext), type.conforms(to: .package) {
            return true
        }

        return false
    }

    static func getSelectedItems(
        selectedIds: Set<String>,
        items: IdentifiedArrayOf<Entry>,
    ) -> [Entry] {
        Array(items.filter { selectedIds.contains($0.id) })
    }

    static func getSelectedFiles(
        selectedIds: Set<String>,
        items: IdentifiedArrayOf<Entry>,
    ) -> [Entry] {
        getSelectedItems(selectedIds: selectedIds, items: items).filter { !$0.isDirectory }
    }

    static func isPackageItem(_ item: Entry) -> Bool {
        guard item.isDirectory else { return false }

        let url = URL(fileURLWithPath: item.fullPath)
        if let values = try? url.resourceValues(forKeys: [.isPackageKey]),
           values.isPackage == true
        {
            return true
        }

        let ext = item.fileExtension.lowercased()
        if ["app", "icon"].contains(ext) {
            return true
        }

        if let type = UTType(filenameExtension: item.fileExtension),
           type.conforms(to: .package)
        {
            return true
        }

        return false
    }

    static func preloadApplicationsEffect(
        selectedIds: Set<String>,
        items: IdentifiedArrayOf<Entry>,
        currentItemId: String? = nil,
    ) -> Effect<EntryAction> {
        let selectedFiles = getSelectedFiles(selectedIds: selectedIds, items: items)

        if selectedFiles.count > 1 {
            return .send(.delegate(.intent(.loadCommonApplicationsForFiles(files: selectedFiles))))
        } else if selectedFiles.count == 1, let file = selectedFiles.first {
            return .send(.delegate(.intent(.loadApplicationsForFile(file: file))))
        } else if let itemId = currentItemId,
                  let item = items.first(where: { $0.id == itemId }),
                  !item.isDirectory
        {
            return .send(.delegate(.intent(.loadApplicationsForFile(file: item))))
        }

        return .none
    }
}

nonisolated enum EntryCancelID: Hashable, Sendable {
    case fileSystemObserver
    case fsEventsWatcher
}
