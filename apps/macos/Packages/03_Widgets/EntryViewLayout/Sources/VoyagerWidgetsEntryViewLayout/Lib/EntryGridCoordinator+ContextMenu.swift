@preconcurrency import AppKit
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations

extension EntryGridCoordinator {
    func preloadOpenWithApplications(selectedEntries: [EntryModel]) {
        store.send(.view(.preloadOpenWithApplications(selectedEntries)))
    }

    func openWithApplications(selectedEntries _: [EntryModel]) -> [ApplicationInfo] {
        state.entryOperations.commonApplicationsForSelectedFiles
    }

    func updateContextMenuAnchor(_ event: NSEvent) {
        if let window = view?.window {
            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            contextMenuAnchor = screenPoint
        } else {
            contextMenuAnchor = nil
        }
    }
}
