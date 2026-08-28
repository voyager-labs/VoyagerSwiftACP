import VoyagerEntitiesEntry
import VoyagerShared

public extension EntryModel {
    var supportsListHierarchyExpansion: Bool {
        isFolder && !isPackage && fileExtension.lowercased() != CollectionConstants.fileExtension
    }
}
