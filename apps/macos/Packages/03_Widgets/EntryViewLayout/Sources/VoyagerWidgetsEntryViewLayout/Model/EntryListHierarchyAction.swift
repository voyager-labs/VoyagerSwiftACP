import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

public enum EntryLoadFailure: Error, Equatable, Sendable {
    case permissionDenied
    case unavailable(description: String)
}

@CasePathable
public enum EntryListHierarchyAction: CasePathable, Sendable {
    case rootContextChanged(path: String)
    case hiddenFilesSettingChanged
    case arrangementMetadataPriorityChanged
    case hierarchyInvalidated(affectedPaths: [String], removedPrefixes: [String])
    case coarseHierarchyInvalidated(removedPrefixes: [String], retainsCompleteSnapshots: Bool = false)
    case coarseHierarchyRefreshRequested
    case restartUnfinishedExpandedFolderLoads
    case rootSnapshotCompleted(rootContextGeneration: Int, rootFolders: [EntryModel])
    case folderExpansionRequested(id: EntryModel.ID)
    case folderCollapseRequested(id: EntryModel.ID)
    case folderRetryRequested(id: EntryModel.ID)
    case folderChildrenResponse(
        rootContextGeneration: Int,
        folderID: EntryModel.ID,
        folderGeneration: Int,
        EntryListFolderChildrenResponse,
    )
}

public enum EntryListFolderChildrenResponse: Equatable, Sendable {
    case event(EntryLoadEvent)
    case streamCompleted
    case failed(EntryLoadFailure)
}
