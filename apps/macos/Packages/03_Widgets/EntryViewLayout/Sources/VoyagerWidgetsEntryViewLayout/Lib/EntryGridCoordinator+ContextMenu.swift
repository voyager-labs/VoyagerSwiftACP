@preconcurrency import AppKit
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations

extension EntryGridCoordinator {
    func preloadOpenWithApplications(selectedEntries: [EntryModel]) {
        let selectedFiles = selectedEntries.filter { !$0.isFolder }
        if selectedFiles.isEmpty {
            return
        }

        if selectedFiles.count > 1 {
            sendEntryOperations(.openWith(.loadCommonApplicationsForFiles(files: selectedFiles)))
        } else if let file = selectedFiles.first,
                  state.entryOperations
                  .applicationsForTypes[UTType(filenameExtension: file.fileExtension)?.identifier ?? UTType.data
                      .identifier] == nil
        {
            sendEntryOperations(.openWith(.loadApplicationsForFile(file: file)))
        }
    }

    func openWithApplications(selectedEntries: [EntryModel]) -> [ApplicationInfo] {
        let selectedFiles = selectedEntries.filter { !$0.isFolder }
        return if selectedFiles.count > 1 {
            state.entryOperations.commonApplicationsForSelectedFiles
        } else if let file = selectedFiles.first {
            state.entryOperations
                .applicationsForTypes[UTType(filenameExtension: file.fileExtension)?.identifier ?? UTType.data
                    .identifier] ?? []
        } else {
            []
        }
    }

    func updateContextMenuAnchor(_ event: NSEvent) {
        if let window = view?.window {
            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            contextMenuAnchor = screenPoint
        } else {
            contextMenuAnchor = nil
        }
    }

    func dragOperation(from resolved: EntryDropResolvedOperation) -> NSDragOperation {
        switch resolved {
        case .none:
            []
        case .copy:
            .copy
        case .move:
            .move
        }
    }
}
