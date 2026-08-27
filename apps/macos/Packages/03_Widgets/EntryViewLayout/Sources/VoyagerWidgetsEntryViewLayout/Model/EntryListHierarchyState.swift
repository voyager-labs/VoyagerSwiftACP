import Foundation
import VoyagerEntitiesEntry

public typealias EntryListHierarchyFailure = EntryLoadFailure

/// Folder의 children + metadata snapshot.
/// load 완료 여부와 관계없이 현재까지 수신된 children을 보유한다.
public struct FolderSnapshot: Equatable, Sendable {
    public var children: [EntryModel]
    public var expectedBatchIndex: Int
    public var coreFinished: Bool
    /// 이번 generation에서 내용(non-empty) core batch를 한 번이라도 적용했는지 여부.
    /// startLoad가 이전 세대 완료 스냅샷을 보존(retained)할 때 false로 유지되어,
    /// 아직 새 내용을 받지 않은 상태에서 첫 내용 배치가 retained children을 교체하도록 표시한다.
    public var hasAppliedContentBatch: Bool

    public init(
        children: [EntryModel] = [],
        expectedBatchIndex: Int = 0,
        coreFinished: Bool = false,
        hasAppliedContentBatch: Bool = false,
    ) {
        self.children = children
        self.expectedBatchIndex = expectedBatchIndex
        self.coreFinished = coreFinished
        self.hasAppliedContentBatch = hasAppliedContentBatch
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

public struct DeferredFolderReplacement: Equatable, Sendable {
    public let untilEntryID: EntryModel.ID
    public var stagedChildren: [EntryModel]
    /// 보존(preservation) 소유자 폴더처럼 migration 완료까지 staging을 보류해야 하는지 여부.
    /// true면 해당 폴더의 coreFinished가 terminal만 기록하고 retained children과 staging을 유지하며,
    /// 실제 커밋은 destination migration(migrateSelection)이 담당한다.
    public let holdsUntilMigration: Bool

    public init(
        untilEntryID: EntryModel.ID,
        stagedChildren: [EntryModel] = [],
        holdsUntilMigration: Bool = false,
    ) {
        self.untilEntryID = untilEntryID
        self.stagedChildren = stagedChildren
        self.holdsUntilMigration = holdsUntilMigration
    }
}

public struct EntryListHierarchyState: Equatable, Sendable {
    var deferredFolderReplacements: [EntryModel.ID: DeferredFolderReplacement] = [:]

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
        deferredFolderReplacements = [:]
    }

    public mutating func beginDeferredFolderReplacement(
        folderID: EntryModel.ID,
        untilEntryID: EntryModel.ID,
        holdsUntilMigration: Bool = false,
    ) {
        guard deferredFolderReplacements[folderID] == nil else { return }
        deferredFolderReplacements[folderID] = .init(
            untilEntryID: untilEntryID,
            holdsUntilMigration: holdsUntilMigration,
        )
    }

    public mutating func takeDeferredFolderReplacement(folderID: EntryModel.ID) -> [EntryModel]? {
        deferredFolderReplacements.removeValue(forKey: folderID)?.stagedChildren
    }

    public mutating func discardDeferredFolderReplacement(folderID: EntryModel.ID) {
        deferredFolderReplacements.removeValue(forKey: folderID)
    }

    public func deferredFolderReplacement(folderID: EntryModel.ID) -> DeferredFolderReplacement? {
        deferredFolderReplacements[folderID]
    }

    public mutating func discardAllDeferredFolderReplacements() {
        deferredFolderReplacements = [:]
    }

    /// 전이 취소 시 staging을 그대로 버리지 않고 폴더에 반영한다.
    /// staging 누적 동안 expectedBatchIndex가 증가했으므로 이를 폐기하면 같은 세대의
    /// 후속 batch가 generic 경로에서 cursor 어긋남 없이 처리되기 위해 누적 결과가 필요하다.
    /// 빈 staging은 authoritative 내용이 아니므로 retained children을 건드리지 않는다.
    public mutating func commitDeferredFolderReplacementsOnCancel() {
        for (folderID, replacement) in deferredFolderReplacements {
            guard var node = nodesByID[folderID], !replacement.stagedChildren.isEmpty else { continue }
            node.folder.children = replacement.stagedChildren
            node.folder.hasAppliedContentBatch = true
            nodesByID[folderID] = node
        }
        deferredFolderReplacements = [:]
    }
}

// MARK: - Convenience init for FolderNodeState

public extension FolderNodeState {
    /// children + loadPhase + generation + expectedBatchIndex + coreFinished를 folder: FolderSnapshot으로 변환한다.
    /// children과 loadPhase가 required이므로 canonical init과의 ambiguity가 없다.
    /// hasAppliedContentBatch는 생략 시 테스트 편의 의미로 유추한다(내용 존재 + 진행 상태).
    init(
        children: [EntryModel],
        loadPhase: FolderLoadPhase,
        generation: Int,
        expectedBatchIndex: Int = 0,
        coreFinished: Bool = false,
        hasAppliedContentBatch: Bool? = nil,
    ) {
        let appliedContent = hasAppliedContentBatch ?? {
            let hasContent = !children.isEmpty
            let progressed = loadPhase == .loaded
                || loadPhase == .enriching
                || coreFinished
                || expectedBatchIndex > 0
            return hasContent && progressed
        }()
        folder = FolderSnapshot(
            children: children,
            expectedBatchIndex: expectedBatchIndex,
            coreFinished: coreFinished,
            hasAppliedContentBatch: appliedContent,
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
