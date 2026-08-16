import Foundation
import VoyagerEntitiesEntry

public typealias EntryListHierarchyFailure = EntryLoadFailure

/// Folder의 children + metadata snapshot.
/// load 완료 여부와 관계없이 현재까지 수신된 children을 보유한다.
public struct FolderSnapshot: Equatable, Sendable {
    public var children: [EntryModel]
    public var expectedBatchIndex: Int
    public var coreFinished: Bool

    public init(
        children: [EntryModel] = [],
        expectedBatchIndex: Int = 0,
        coreFinished: Bool = false,
    ) {
        self.children = children
        self.expectedBatchIndex = expectedBatchIndex
        self.coreFinished = coreFinished
    }
}

/// Folder load의 진행 상태.
/// phase 전이는 항상 순방향이어야 하며, 역방향 전이는 invalid event로 간주한다.
public enum FolderLoadPhase: Equatable, Sendable {
    case idle
    case loadingCore
    case enriching
    case loaded
    case failed(EntryListHierarchyFailure)
}

/// nodesByID에서 각 folder node의 상태를 표현한다.
/// expansionIntent, loadPhase, snapshot을 하나의 struct로 묶어
/// expandedFolderIDs와 foldersByID의 병렬 상태를 제거한다.
public struct FolderNodeState: Equatable, Sendable {
    public var folder: FolderSnapshot
    public var parentID: EntryModel.ID?
    public var expansionIntent: Bool
    public var generation: Int
    public var loadPhase: FolderLoadPhase

    public init(
        folder: FolderSnapshot = .init(),
        parentID: EntryModel.ID? = nil,
        expansionIntent: Bool = false,
        generation: Int = 0,
        loadPhase: FolderLoadPhase = .idle,
    ) {
        self.folder = folder
        self.parentID = parentID
        self.expansionIntent = expansionIntent
        self.generation = generation
        self.loadPhase = loadPhase
    }
}

public struct EntryListHierarchyState: Equatable, Sendable {
    public private(set) var rootContextGeneration: Int
    public private(set) var rootPath: String

    /// 단일 source of truth: folder ID -> node state.
    /// expansionIntent, cached snapshot, generation, load phase를 모두 포함한다.
    public var nodesByID: [EntryModel.ID: FolderNodeState]

    /// expandedFolderIDs는 nodesByID에서 expansionIntent == true인 ID만 반환하는 읽기 전용 computed property.
    /// 외부에서 직접 쓸 수 없으며, 모든 mutation은 reducer action 또는 test-only helper를 통해 nodesByID에 적용된다.
    public var expandedFolderIDs: Set<EntryModel.ID> {
        Set(nodesByID.filter(\.value.expansionIntent).map(\.key))
    }

    public init(
        rootContextGeneration: Int = 0,
        rootPath: String = "",
        nodesByID: [EntryModel.ID: FolderNodeState] = [:],
    ) {
        self.rootContextGeneration = rootContextGeneration
        self.rootPath = rootPath
        self.nodesByID = nodesByID
    }

    public mutating func replaceRoot(path: String) {
        if !rootPath.isEmpty, !path.isEmpty {
            let currentPath = URL(fileURLWithPath: rootPath).standardizedFileURL.path
            let replacementPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard currentPath != replacementPath else { return }
        }
        rootContextGeneration &+= 1
        rootPath = path
        nodesByID = [:]
    }
}

// MARK: - Convenience init for FolderNodeState

public extension FolderNodeState {
    /// children + loadPhase + generation + expectedBatchIndex + coreFinished를 folder: FolderSnapshot으로 변환한다.
    /// children과 loadPhase가 required이므로 canonical init과의 ambiguity가 없다.
    init(
        children: [EntryModel],
        loadPhase: FolderLoadPhase,
        generation: Int,
        expectedBatchIndex: Int = 0,
        coreFinished: Bool = false,
    ) {
        folder = FolderSnapshot(
            children: children,
            expectedBatchIndex: expectedBatchIndex,
            coreFinished: coreFinished,
        )
        self.generation = generation
        self.loadPhase = loadPhase
        expansionIntent = false
        parentID = nil
    }
}

// MARK: - Test support

public extension EntryListHierarchyState {
    /// Test support: expansion intent를 설정한다.
    /// 지정된 ID의 nodesByID entry를 생성하거나 업데이트한다.
    /// Production code에서는 reducer action을 통해 mutation한다.
    mutating func setExpandedIDs(_ ids: Set<EntryModel.ID>) {
        for id in nodesByID.keys {
            nodesByID[id]?.expansionIntent = ids.contains(id)
        }
        for id in ids where nodesByID[id] == nil {
            nodesByID[id] = FolderNodeState(expansionIntent: true)
        }
    }
}
