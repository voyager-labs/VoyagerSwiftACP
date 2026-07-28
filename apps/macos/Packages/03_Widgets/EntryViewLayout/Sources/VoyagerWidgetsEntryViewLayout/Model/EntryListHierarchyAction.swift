import CasePaths
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
    case coarseHierarchyInvalidated(removedPrefixes: [String])
    case coarseHierarchyRefreshRequested
    case rootSnapshotCompleted(rootFolderIDs: Set<EntryModel.ID>)
    case showHiddenFilesRefreshRequested
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
