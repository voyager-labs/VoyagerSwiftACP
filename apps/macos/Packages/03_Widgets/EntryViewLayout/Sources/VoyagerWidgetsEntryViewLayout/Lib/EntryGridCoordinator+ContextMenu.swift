@preconcurrency import AppKit
import VoyagerEntitiesEntry

extension EntryGridCoordinator {
    func preloadOpenWithApplications(selectedEntries _: [EntryModel]) {
        // Open-with applications are now loaded by the Page bridge (Wave 2)
    }

    func openWithApplications(selectedEntries _: [EntryModel]) -> [ApplicationInfo] {
        []
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
