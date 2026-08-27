import Foundation

public struct ExternalContentTabReservation: Equatable, Sendable {
    public let id: ContentTabID
    public let anchor: ContentTabPageAnchor
    public let pendingSelectEntryID: String?

    public init(
        id: ContentTabID,
        anchor: ContentTabPageAnchor,
        pendingSelectEntryID: String? = nil,
    ) {
        self.id = id
        self.anchor = anchor
        self.pendingSelectEntryID = pendingSelectEntryID
    }
}

public extension FileManagerWindowState {
    @discardableResult
    mutating func reserveExternalContentTabs(
        _ reservations: [ExternalContentTabReservation],
    ) -> Bool {
        guard pendingContentTabClose == nil,
              Self.canReserveExternalContentTabs(
                  reservations,
                  existingIDs: Set(contentTabs.tabs.ids),
                  existingCount: contentTabs.tabs.count,
              ) else { return false }

        let previousActiveTabID = contentTabs.activeTabID
        let windowContext = content
        var updatedTabs = contentTabs.tabs
        var updatedContentStates = tabContentStates
        var updatedInspectorStates = tabInspectorStates

        if let previousActiveTabID {
            updatedContentStates[previousActiveTabID] = content
            if supportsInspector(tabID: previousActiveTabID) {
                updatedInspectorStates[previousActiveTabID] = inspector.tabSnapshot()
            } else {
                updatedInspectorStates[previousActiveTabID] = nil
            }
        }

        let snapshots = Self.externalSnapshots(
            for: reservations,
            inheritingWindowContextFrom: windowContext,
        )
        for reservation in reservations {
            updatedTabs.append(ContentTabItem.makeExternalReservation(
                id: reservation.id,
                anchor: reservation.anchor,
            ))
            updatedContentStates[reservation.id] = snapshots.content[reservation.id]
            updatedInspectorStates[reservation.id] = snapshots.inspector[reservation.id]
        }

        contentTabs.tabs = updatedTabs
        tabContentStates = updatedContentStates
        tabInspectorStates = updatedInspectorStates
        syncContentTabSidebarItems()
        return true
    }

    static func canReserveExternalContentTabs(
        _ reservations: [ExternalContentTabReservation],
        existingIDs: Set<ContentTabID>,
        existingCount: Int,
    ) -> Bool {
        guard !reservations.isEmpty,
              existingCount + reservations.count <= ContentTabConstants.maxTabs
        else { return false }

        var reservedIDs = Set<ContentTabID>()
        for reservation in reservations {
            guard !reservation.id.rawValue.isEmpty,
                  !existingIDs.contains(reservation.id),
                  reservedIDs.insert(reservation.id).inserted,
                  reservation.isValidExternalReservation
            else { return false }
        }
        return true
    }

    static func externalSnapshots(
        for reservations: [ExternalContentTabReservation],
        inheritingWindowContextFrom windowContext: FileManagerContentFeature.State,
    ) -> (
        content: [ContentTabID: FileManagerContentFeature.State],
        inspector: [ContentTabID: FileManagerInspectorFeature.State],
    ) {
        var contentSnapshots: [ContentTabID: FileManagerContentFeature.State] = [:]
        var inspectorSnapshots: [ContentTabID: FileManagerInspectorFeature.State] = [:]
        for reservation in reservations {
            var content = FileManagerContentFeature.State.initialContent(
                for: reservation.anchor,
                inheritingWindowContextFrom: windowContext,
            )
            content.setPendingEntrySelection(entryID: reservation.pendingSelectEntryID, destinationPath: nil)
            contentSnapshots[reservation.id] = content
            inspectorSnapshots[reservation.id] = FileManagerInspectorFeature.State().tabSnapshot()
        }
        return (contentSnapshots, inspectorSnapshots)
    }
}

extension ExternalContentTabReservation {
    var isValidExternalReservation: Bool {
        if let pendingSelectEntryID,
           pendingSelectEntryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return false
        }

        switch anchor {
        case let .directory(path):
            guard NSString(string: path).isAbsolutePath else { return false }
            guard let pendingSelectEntryID else { return true }
            guard NSString(string: pendingSelectEntryID).isAbsolutePath else { return false }
            let directoryURL = URL(fileURLWithPath: path).standardizedFileURL
            let selectionParentURL = URL(fileURLWithPath: pendingSelectEntryID)
                .standardizedFileURL
                .deletingLastPathComponent()
            return selectionParentURL.path == directoryURL.path
        case let .collectionFile(url):
            return url.isFileURL
                && NSString(string: url.path).isAbsolutePath
                && pendingSelectEntryID == nil
        case .homeDefault,
             .virtualCollection,
             .aiChat:
            return false
        }
    }
}
