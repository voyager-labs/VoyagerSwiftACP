import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    /// EVM-002-replacement_reload_snapshot_retention: 보류 staging에도 metadata patch를 적용한다.
    /// - 검증 내용: held terminal 이후 metadataPatches가 retained children과 staged children 모두에 반영된다.
    /// - 사전 조건: holdsUntilMigration 스테이징 폴더가 coreFinished에 도달한 뒤 metadata patch 응답을 받는다.
    /// - 기대 결과: staged children도 patch가 반영되어 migration 커밋 시 metadata가 되돌아가지 않는다.
    func testHeldStagingReceivesMetadataPatches() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let before = stagedMetadataFile(id: "/root/a/before", name: "before")
        let kept = stagedMetadataFile(id: "/root/a/kept", name: "kept")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [before], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )
        state.hierarchy.beginDeferredFolderReplacement(
            folderID: folder.id as String,
            untilEntryID: "/root/a/after",
            holdsUntilMigration: true,
        )
        _ = reducer.reduce(
            into: &state,
            action: heldStagingFolderResponse(
                folder.id,
                .event(.coreBatch(items: [kept], batchIndex: 0)),
            ),
        )
        _ = reducer.reduce(
            into: &state,
            action: heldStagingFolderResponse(
                folder.id,
                .event(.coreFinished(batchCount: 1)),
            ),
        )

        let patches = [
            EntryMetadataPatch.spotlight(
                id: before.id,
                kind: "PatchedBefore",
                creatorApplication: nil,
                lastOpenedDate: nil,
            ),
            EntryMetadataPatch.spotlight(
                id: kept.id,
                kind: "PatchedKept",
                creatorApplication: nil,
                lastOpenedDate: nil,
            ),
        ]
        _ = reducer.reduce(
            into: &state,
            action: heldStagingFolderResponse(
                folder.id,
                .event(.metadataPatches(patches)),
            ),
        )

        XCTAssertEqual(
            state.hierarchy.nodesByID[folder.id as String]?.folder.children.first?.facets.kind,
            "PatchedBefore",
            "retained children에도 patch가 적용된다",
        )
        XCTAssertEqual(
            state.hierarchy.deferredFolderReplacements[folder.id as String]?.stagedChildren.first?.facets.kind,
            "PatchedKept",
            "보류 staging에도 patch가 적용되어 migration 커밋 시 metadata가 유지된다",
        )
    }

    private func heldStagingFolderResponse(
        _ folderID: EntryModel.ID,
        _ response: EntryListFolderChildrenResponse,
    ) -> EntryViewLayoutAction {
        .hierarchy(.folderChildrenResponse(
            rootContextGeneration: 0,
            folderID: folderID,
            folderGeneration: 4,
            response,
        ))
    }

    private func stagedMetadataFile(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "txt",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
