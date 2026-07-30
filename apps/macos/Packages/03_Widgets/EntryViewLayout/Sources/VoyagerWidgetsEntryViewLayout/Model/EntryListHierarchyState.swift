import Foundation
import VoyagerEntitiesEntry

public typealias EntryListHierarchyFailure = EntryLoadFailure

public struct EntryListHierarchyState: Equatable, Sendable {
    public enum ChildrenPhase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(EntryListHierarchyFailure)
    }

    public struct FolderChildrenState: Equatable, Sendable {
        public var children: [EntryModel]
        public var phase: ChildrenPhase
        public var generation: Int
        public var expectedBatchIndex: Int
        public var coreFinished: Bool

        public init(
            children: [EntryModel] = [],
            phase: ChildrenPhase = .idle,
            generation: Int = 0,
            expectedBatchIndex: Int = 0,
            coreFinished: Bool = false,
        ) {
            self.children = children
            self.phase = phase
            self.generation = generation
            self.expectedBatchIndex = expectedBatchIndex
            self.coreFinished = coreFinished
        }
    }

    public private(set) var rootContextGeneration: Int
    public private(set) var rootPath: String
    public var expandedFolderIDs: Set<EntryModel.ID>
    public var foldersByID: [EntryModel.ID: FolderChildrenState]

    public init(
        rootContextGeneration: Int = 0,
        rootPath: String = "",
        expandedFolderIDs: Set<EntryModel.ID> = [],
        foldersByID: [EntryModel.ID: FolderChildrenState] = [:],
    ) {
        self.rootContextGeneration = rootContextGeneration
        self.rootPath = rootPath
        self.expandedFolderIDs = expandedFolderIDs
        self.foldersByID = foldersByID
    }

    public mutating func replaceRoot(path: String) {
        rootContextGeneration &+= 1
        rootPath = path
        expandedFolderIDs = []
        foldersByID = [:]
    }
}
