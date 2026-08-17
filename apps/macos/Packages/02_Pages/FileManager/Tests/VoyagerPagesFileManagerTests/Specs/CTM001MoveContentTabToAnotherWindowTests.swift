import Foundation
import IdentifiedCollections
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM001MoveContentTabToAnotherWindowTests: XCTestCase {
    // MARK: - CTM-001-move_content_tab_to_another_file_manager_window

    /// CTM-001-move_content_tab_to_another_file_manager_window: active tab은 valid previous를 source fallback으로 사용한다.
    /// 기존 Page work unit의 source owner 제거와 post-commit rebind intent를 검증한다.
    /// - 검증 내용: read-only preflight, source Content/Inspector/AI/pin owner 제거, fallback, rebind intent
    /// - 사전 조건: 세 tab source, 한 tab target, moved tab은 pinned이며 settled AI session/messages와 background owner를 가짐
    /// - 기대 결과: source moved owner 0, unrelated owner 불변, valid previous active, undo/navigation rebind intent 반환
    func testApplyMovesCompleteActiveWorkUnitAndUsesValidPreviousFallback() throws {
        let scenario = CompleteTransferScenario()
        let sourceBefore = scenario.source
        let targetBefore = scenario.target

        let preflight = ContentTabTransfer.preflight(
            source: scenario.source,
            target: scenario.target,
            tabID: scenario.movedID,
        )
        XCTAssertEqual(scenario.source, sourceBefore)
        XCTAssertEqual(scenario.target, targetBefore)
        let postCommit = try ContentTabTransfer.apply(preflight.successToken()).movedPostCommit()

        XCTAssertEqual(postCommit.source.contentTabs.activeTabID, scenario.previousID)
        XCTAssertNil(postCommit.source.contentTabs.previousActiveTabID)
        XCTAssertNil(postCommit.source.contentTabs.tabs[id: scenario.movedID])
        XCTAssertNil(postCommit.source.tabContentStates[scenario.movedID])
        XCTAssertNil(postCommit.source.tabInspectorStates[scenario.movedID])
        XCTAssertNil(postCommit.source.contentTabs.pinnedRecords[scenario.movedID])
        XCTAssertNil(postCommit.source.backgroundAiChatStates[scenario.sessionID])
        XCTAssertNil(postCommit.source.backgroundInspectorAiChatStates[scenario.sessionID])
        XCTAssertEqual(
            postCommit.source.backgroundAiChatStates[scenario.unrelatedSessionID],
            scenario.unrelatedBackground,
        )
        XCTAssertEqual(
            postCommit.source.backgroundInspectorAiChatStates[scenario.unrelatedSessionID],
            scenario.unrelatedInspectorBackground,
        )
        XCTAssertEqual(postCommit.rebind.sourceWindowID, Fixture.sourceWindowID)
        XCTAssertEqual(postCommit.rebind.targetWindowID, Fixture.targetWindowID)
        XCTAssertEqual(postCommit.rebind.tabID, scenario.movedID)
        XCTAssertEqual(postCommit.rebind.sourceActiveNavigationObservation?.windowID, Fixture.sourceWindowID)
        XCTAssertEqual(postCommit.rebind.sourceActiveNavigationObservation?.tabID, scenario.previousID)
        XCTAssertEqual(postCommit.rebind.targetActiveNavigationObservation.windowID, Fixture.targetWindowID)
        XCTAssertEqual(postCommit.rebind.targetActiveNavigationObservation.tabID, scenario.movedID)
        XCTAssertTrue(postCommit.rebind.rebindNavigationObservation)
        XCTAssertTrue(postCommit.rebind.rebindUndoScope)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: complete work unit identity가 target에서 유지된다.
    /// pinned tab이 target 기존 순서를 보존하며 pinned domain 끝에 배치되는지 검증한다.
    /// - 검증 내용: exact tab/pin/Content/Inspector/AI identity, target active/previous, destination context,
    /// recently-closed 불변
    /// - 사전 조건: settled AI transcript와 pinned record를 포함한 complete transfer scenario
    /// - 기대 결과: target owner 1, moved tab active, 기존 target active가 previous이며 양 window close history 불변
    func testApplyPreservesCompleteTargetIdentityAndCloseHistory() throws {
        let scenario = CompleteTransferScenario()
        let postCommit = try scenario.postCommit()

        XCTAssertEqual(
            Array(postCommit.target.contentTabs.tabs.ids),
            [scenario.movedID, scenario.targetID],
        )
        XCTAssertEqual(postCommit.target.contentTabs.tabs[id: scenario.movedID], scenario.movedTab)
        XCTAssertEqual(postCommit.target.contentTabs.activeTabID, scenario.movedID)
        XCTAssertEqual(postCommit.target.contentTabs.previousActiveTabID, scenario.targetID)
        XCTAssertEqual(postCommit.target.contentTabs.pinnedRecords[scenario.movedID], scenario.pinRecord)
        var expectedContent = scenario.movedContent
        expectedContent.entryViewLayout.entryOperations.windowID = Fixture.targetWindowID
        XCTAssertEqual(postCommit.target.tabContentStates[scenario.movedID], expectedContent)
        XCTAssertEqual(postCommit.target.content, expectedContent)
        XCTAssertTrue(scenario.movedContent.collection.isDirty)
        XCTAssertEqual(
            postCommit.target.content.collection.collectionSession.metadata.reopenContext,
            scenario.movedContent.collection.collectionSession.metadata.reopenContext,
        )
        XCTAssertEqual(
            postCommit.target.content.entryViewLayout.entryOperations.undoRecords,
            scenario.movedContent.entryViewLayout.entryOperations.undoRecords,
        )
        XCTAssertEqual(
            postCommit.target.content.entryViewLayout.entryOperations.redoRecords,
            scenario.movedContent.entryViewLayout.entryOperations.redoRecords,
        )
        XCTAssertEqual(postCommit.target.tabContentStates[scenario.movedID]?.aiChat.sessionID, scenario.sessionID)
        XCTAssertEqual(
            postCommit.target.tabContentStates[scenario.movedID]?.aiChat.transcriptHistory,
            scenario.movedContent.aiChat.transcriptHistory,
        )
        XCTAssertEqual(postCommit.target.tabInspectorStates[scenario.movedID], scenario.movedInspector)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: 이동 후 양쪽 window의 MRU 순서를 보존한다.
    /// source에서는 moved identity를 제거하고 target에서는 moved primary를 기존 history 앞에 기록하는지 검증한다.
    /// - 검증 내용: source stale identity prune, fallback 우선순위, target 기존 MRU 상대 순서
    /// - 사전 조건: source와 target이 각각 세 단계와 두 단계의 최근 사용 기록을 보유함
    /// - 기대 결과: source는 fallback부터 생존 순서, target은 moved primary부터 기존 순서를 유지함
    func testApplyPreservesWindowLocalRecentlyUsedOrder() throws {
        let sourceFallbackID = ContentTabID(rawValue: "source-fallback")
        let movedID = ContentTabID(rawValue: "moved")
        let sourceOlderID = ContentTabID(rawValue: "source-older")
        let targetActiveID = ContentTabID(rawValue: "target-active")
        let targetOlderID = ContentTabID(rawValue: "target-older")
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(sourceFallbackID, path: "/source-fallback"),
                Fixture.tab(movedID, path: "/moved"),
                Fixture.tab(sourceOlderID, path: "/source-older"),
            ],
            active: movedID,
            previous: sourceFallbackID,
        )
        source.contentTabs.recentlyUsedTabIDs = [movedID, sourceFallbackID, sourceOlderID]
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(targetActiveID, path: "/target-active"),
                Fixture.tab(targetOlderID, path: "/target-older"),
            ],
            active: targetActiveID,
        )
        target.contentTabs.recentlyUsedTabIDs = [targetActiveID, targetOlderID]

        let postCommit = try ContentTabTransfer
            .apply(ContentTabTransfer.preflight(source: source, target: target, tabID: movedID).successToken())
            .movedPostCommit()

        XCTAssertEqual(postCommit.source.contentTabs.activeTabID, sourceFallbackID)
        XCTAssertEqual(
            postCommit.source.contentTabs.recentlyUsedTabIDs,
            [sourceFallbackID, sourceOlderID],
        )
        XCTAssertEqual(
            postCommit.target.contentTabs.recentlyUsedTabIDs,
            [movedID, targetActiveID, targetOlderID],
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: background AI owner와 close history가 보존된다.
    /// moved Content/Inspector background owner만 이동하고 unrelated 양쪽 owner는 그대로인지 검증한다.
    /// - 검증 내용: background owner source 0/target 1, unrelated owner equality, destination context, close history
    /// - 사전 조건: source와 target 모두 unrelated background Content/Inspector owner를 보유
    /// - 기대 결과: moved owner는 target에 정확히 한 개, unrelated owner와 recently-closed 값은 불변
    func testApplyMovesBackgroundOwnersExactlyOnceAndPreservesUnrelatedOwners() throws {
        let scenario = CompleteTransferScenario()
        let postCommit = try scenario.postCommit()
        var expectedContent = scenario.movedContent
        expectedContent.entryViewLayout.entryOperations.windowID = Fixture.targetWindowID

        XCTAssertEqual(postCommit.target.backgroundAiChatStates[scenario.sessionID], expectedContent)
        XCTAssertEqual(postCommit.target.backgroundInspectorAiChatStates[scenario.sessionID], scenario.movedInspector)
        XCTAssertEqual(
            postCommit.target.backgroundAiChatStates[scenario.targetUnrelatedSessionID],
            scenario.targetUnrelatedBackground,
        )
        XCTAssertEqual(
            postCommit.target.backgroundInspectorAiChatStates[scenario.targetUnrelatedSessionID],
            scenario.targetUnrelatedInspectorBackground,
        )
        XCTAssertEqual(postCommit.target.content.entryViewLayout.entryOperations.windowID, Fixture.targetWindowID)
        XCTAssertEqual(
            postCommit.target.content.composer.cancellationOwnerID,
            scenario.movedContent.composer.cancellationOwnerID,
        )
        XCTAssertEqual(postCommit.source.contentTabs.recentlyClosed, scenario.source.contentTabs.recentlyClosed)
        XCTAssertEqual(postCommit.source.recentlyClosedNavigationRoute, scenario.source.recentlyClosedNavigationRoute)
        XCTAssertEqual(postCommit.target.contentTabs.recentlyClosed, scenario.target.contentTabs.recentlyClosed)
        XCTAssertEqual(postCommit.target.recentlyClosedNavigationRoute, scenario.target.recentlyClosedNavigationRoute)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: active fallback은 right 다음 left 순서를 따른다.
    /// previous가 유효하지 않을 때 제거 전 index 기준의 deterministic sibling 선택을 검증한다.
    /// - 검증 내용: active-right와 active-left fallback 및 previousActiveTabID 정규화
    /// - 사전 조건: moved tab 오른쪽이 있는 source와 moved tab이 마지막인 source
    /// - 기대 결과: 첫 source는 right, 둘째 source는 left가 active이며 previous는 moved/missing/current를 참조하지 않음
    func testApplyUsesRightThenLeftActiveFallback() throws {
        let leftID = ContentTabID(rawValue: "left")
        let movedID = ContentTabID(rawValue: "moved")
        let rightID = ContentTabID(rawValue: "right")
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)

        let rightSource = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(leftID, path: "/left"),
                Fixture.tab(movedID, path: "/moved"),
                Fixture.tab(rightID, path: "/right"),
            ],
            active: movedID,
        )
        let rightResult = try ContentTabTransfer
            .apply(ContentTabTransfer.preflight(source: rightSource, target: target, tabID: movedID).successToken())
            .movedPostCommit()
        XCTAssertEqual(rightResult.source.contentTabs.activeTabID, rightID)
        XCTAssertNil(rightResult.source.contentTabs.previousActiveTabID)

        let leftSource = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(leftID, path: "/left"), Fixture.tab(movedID, path: "/moved")],
            active: movedID,
            previous: ContentTabID(rawValue: "missing"),
        )
        let leftResult = try ContentTabTransfer
            .apply(ContentTabTransfer.preflight(source: leftSource, target: target, tabID: movedID).successToken())
            .movedPostCommit()
        XCTAssertEqual(leftResult.source.contentTabs.activeTabID, leftID)
        XCTAssertNil(leftResult.source.contentTabs.previousActiveTabID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: inactive tab 이동은 source active를 유지한다.
    /// inactive cache가 canonical owner로 이동하고 source selection은 흔들리지 않는지 검증한다.
    /// - 검증 내용: inactive owner extraction, active 유지, stale previous 정규화
    /// - 사전 조건: active와 inactive 두 tab, previous가 moved tab을 가리키는 source
    /// - 기대 결과: source active 유지, previous nil, target에서 inactive cache 값이 live active owner가 됨
    func testApplyMovesInactiveCachedOwnerWithoutChangingSourceActive() throws {
        let activeID = ContentTabID(rawValue: "active")
        let movedID = ContentTabID(rawValue: "inactive")
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(activeID, path: "/active"), Fixture.tab(movedID, path: "/inactive")],
            active: activeID,
            previous: movedID,
        )
        source.tabContentStates[movedID]?.pendingSelectEntryID = "/inactive/cache-owned.txt"
        let expected = try XCTUnwrap(source.tabContentStates[movedID])
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)

        let result = try ContentTabTransfer
            .apply(ContentTabTransfer.preflight(source: source, target: target, tabID: movedID).successToken())
            .movedPostCommit()

        XCTAssertEqual(result.source.contentTabs.activeTabID, activeID)
        XCTAssertNil(result.source.contentTabs.previousActiveTabID)
        XCTAssertEqual(result.target.content.pendingSelectEntryID, expected.pendingSelectEntryID)
        XCTAssertEqual(result.target.contentTabs.activeTabID, movedID)
        XCTAssertNil(result.target.contentTabs.previousActiveTabID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: pending directory reload tab은 이동 전에 거절한다.
    /// Window-owned reload marker를 source에 고립시키거나 target에서 유실하지 않는 fail-closed 계약을 검증한다.
    /// - 검증 내용: pending reload moved tab의 windowBusy rejection과 source/target 전체 상태 불변
    /// - 사전 조건: inactive Directory tab이 파일 작업 후 pending reload marker를 보유함
    /// - 기대 결과: preflight는 busy로 거절되고 marker와 양 window logical state가 그대로 유지됨
    func testPreflightRejectsPendingDirectoryReloadTabWithoutMutation() throws {
        let activeID = ContentTabID(rawValue: "pending-reload-active")
        let movedID = ContentTabID(rawValue: "pending-reload-moved")
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(activeID, path: "/active"), Fixture.tab(movedID, path: "/pending")],
            active: activeID,
        )
        source.pendingDirectoryReloadTabIDs = [movedID]
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)

        try assertRejected(
            .ineligible(.windowBusy),
            source: source,
            target: target,
            tabID: movedID,
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: last tab 이동은 source close disposition을 반환한다.
    /// Home replacement나 열린 empty source를 만들지 않는 closing 계약을 검증한다.
    /// - 검증 내용: closeSourceWindow disposition과 target logical commit
    /// - 사전 조건: source에 tab 하나, target에 기존 tab 하나
    /// - 기대 결과: source tab list는 비고 Home은 생성되지 않으며 target에는 moved tab이 append됨
    func testApplyLastTabReturnsCloseSourceWindowWithoutHomeReplacement() throws {
        let movedID = ContentTabID(rawValue: "last")
        let targetID = ContentTabID(rawValue: "target")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/last")],
            active: movedID,
        )
        let target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetID, path: "/target")],
            active: targetID,
        )

        let result = try ContentTabTransfer.apply(
            ContentTabTransfer.preflight(source: source, target: target, tabID: movedID).successToken(),
        )
        let postCommit = try result.closeSourceWindowPostCommit()

        XCTAssertTrue(postCommit.source.contentTabs.tabs.isEmpty)
        XCTAssertNil(postCommit.source.contentTabs.activeTabID)
        XCTAssertNil(postCommit.source.contentTabs.previousActiveTabID)
        XCTAssertEqual(postCommit.target.contentTabs.tabs.ids, [targetID, movedID])
        XCTAssertEqual(postCommit.target.contentTabs.activeTabID, movedID)
        XCTAssertNil(postCommit.rebind.sourceActiveNavigationObservation)
        XCTAssertEqual(postCommit.rebind.targetActiveNavigationObservation.tabID, movedID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: source/target identity가 없거나 같으면 reject한다.
    /// window identity 검증이 source mutation보다 먼저 실행되는지 검증한다.
    /// - 검증 내용: source missing, target missing, self target typed rejection과 complete snapshot equality
    /// - 사전 조건: 하나의 valid moved tab을 가진 source와 empty target
    /// - 기대 결과: identity별 정확한 rejection이고 양 window state는 완전히 동일함
    func testPreflightRejectsMissingAndSameWindowIdentityWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "moved")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/moved")],
            active: movedID,
        )
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        var missingSource = source
        missingSource.content.entryViewLayout.entryOperations.windowID = nil
        missingSource.tabContentStates[movedID]?.entryViewLayout.entryOperations.windowID = nil
        try assertRejected(.sourceWindowIdentityMissing, source: missingSource, target: target, tabID: movedID)

        var missingTarget = target
        missingTarget.content.entryViewLayout.entryOperations.windowID = nil
        try assertRejected(.targetWindowIdentityMissing, source: source, target: missingTarget, tabID: movedID)
        try assertRejected(
            .sameWindow,
            source: source,
            target: Fixture.rewindow(target, id: Fixture.sourceWindowID),
            tabID: movedID,
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: preflight identity/owner rejection은 양 state를 보존한다.
    /// mutation 전에 self/capacity/tab/owner collision과 malformed target을 typed reason으로 분류하는지 검증한다.
    /// - 검증 내용: rejection reason과 source/target 전체 snapshot equality
    /// - 사전 조건: 각 rejection 조건만 하나씩 삽입한 source/target fixture
    /// - 기대 결과: 정확한 rejected reason, source/target semantic state 완전 불변
    func testPreflightRejectsIdentityAndOwnerConflictsWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "moved")
        let movedTab = Fixture.tab(movedID, path: "/moved", pinned: true)
        var source = Fixture.window(windowID: Fixture.sourceWindowID, tabs: [movedTab], active: movedID)
        source.contentTabs.pinnedRecords[movedID] = Fixture.pinRecord(for: movedTab)
        var target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)

        try assertRejected(.sourceTabMissing, source: source, target: target, tabID: ContentTabID(rawValue: "missing"))
        let capacityTabs = (0 ..< ContentTabConstants.maxTabs).map {
            Fixture.tab(ContentTabID(rawValue: "capacity-\($0)"), path: "/capacity/\($0)")
        }
        let capacityTarget = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: capacityTabs,
            active: capacityTabs[0].id,
        )
        try assertRejected(.targetCapacityExceeded, source: source, target: capacityTarget, tabID: movedID)

        target.tabContentStates[movedID] = FileManagerContentState.initialContent(for: .directory(path: "/collision"))
        try assertRejected(.targetOwnerCollision, source: source, target: target, tabID: movedID)
        target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(movedID, path: "/collision")],
            active: movedID,
        )
        try assertRejected(.targetTabCollision, source: source, target: target, tabID: movedID)

        let malformedTargetID = ContentTabID(rawValue: "malformed-target")
        target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(malformedTargetID, path: "/malformed-target")],
            active: malformedTargetID,
        )
        target.tabContentStates[malformedTargetID] = nil
        try assertRejected(.targetMalformedOwnership, source: source, target: target, tabID: movedID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: pin parity와 malformed source는 apply token을 만들지 않는다.
    /// source work unit completeness가 mutation 전에 fail-closed인지 검증한다.
    /// - 검증 내용: pin-record collision/parity 및 missing content owner rejection
    /// - 사전 조건: pinned record collision target, missing pin source, missing content source
    /// - 기대 결과: typed rejection이며 source/target snapshot 불변
    func testPreflightRejectsPinAndMalformedSourceWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "moved")
        let movedTab = Fixture.tab(movedID, path: "/moved", pinned: true)
        var source = Fixture.window(windowID: Fixture.sourceWindowID, tabs: [movedTab], active: movedID)
        source.contentTabs.pinnedRecords[movedID] = Fixture.pinRecord(for: movedTab)
        var target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        target.contentTabs.pinnedRecords[movedID] = Fixture.pinRecord(for: movedTab)
        try assertRejected(.targetPinCollision, source: source, target: target, tabID: movedID)

        source.contentTabs.pinnedRecords[movedID] = nil
        target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        try assertRejected(.sourcePinParity, source: source, target: target, tabID: movedID)

        source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/moved")],
            active: movedID,
        )
        source.tabContentStates[movedID] = nil
        try assertRejected(.ineligible(.malformedOwnership), source: source, target: target, tabID: movedID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: Task 1 eligibility와 AI session collision을 preflight가
    /// 재사용한다.
    /// durable pending owner와 target session collision이 apply token을 만들지 않는지 검증한다.
    /// - 검증 내용: eligibility rejection wrapping, session owner collision, read-only snapshots
    /// - 사전 조건: pending close source 및 같은 settled AI session을 소유한 target
    /// - 기대 결과: typed rejection이고 양 state가 변경되지 않음
    func testPreflightRejectsEligibilityAndSessionCollisionWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "moved")
        let sessionID = AiChatSessionID(rawValue: Fixture.sessionUUID)
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/moved")],
            active: movedID,
        )
        source.content.aiChat.sessionID = sessionID
        source.tabContentStates[movedID] = source.content
        let targetID = ContentTabID(rawValue: "target")
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetID, path: "/target")],
            active: targetID,
        )
        target.content.aiChat.sessionID = sessionID
        target.tabContentStates[targetID] = target.content
        try assertRejected(.targetSessionCollision, source: source, target: target, tabID: movedID)

        source.content.aiChat.sessionID = nil
        source.tabContentStates[movedID] = source.content
        source.pendingContentTabClose = PendingContentTabClose(tabID: movedID)
        target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        try assertRejected(.ineligible(.pendingContentTabClose), source: source, target: target, tabID: movedID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: source의 모든 durable pending category를 reject한다.
    /// close/pin/Collection/AI pending 분류가 source preflight에서 손실 없이 매핑되는지 검증한다.
    /// - 검증 내용: source 네 pending category의 typed rejection과 complete source/target snapshot equality
    /// - 사전 조건: source의 valid tab에 category별 pending state 하나만 설정
    /// - 기대 결과: 각 category가 정확히 reject되고 어떤 state도 변경되지 않음
    func testPreflightRejectsAllTask1PendingCategoriesWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "moved")
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/moved")],
            active: movedID,
        )
        source.pendingContentTabClose = PendingContentTabClose(tabID: movedID)
        try assertRejected(.ineligible(.pendingContentTabClose), source: source, target: target, tabID: movedID)

        source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/moved")],
            active: movedID,
        )
        source.contentTabs.pendingPinnedRecordIDs = [movedID]
        try assertRejected(.ineligible(.pendingPinnedRecordPersistence), source: source, target: target, tabID: movedID)

        source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/moved")],
            active: movedID,
        )
        source.content.collection.isSaving = true
        source.tabContentStates[movedID] = source.content
        try assertRejected(.ineligible(.pendingCollectionOperation), source: source, target: target, tabID: movedID)

        source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/moved")],
            active: movedID,
        )
        source.content.aiChat.streamingAssistantDraft = "streaming"
        source.tabContentStates[movedID] = source.content
        try assertRejected(.ineligible(.pendingAiChatOperation), source: source, target: target, tabID: movedID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: destination의 durable pending category를 reject한다.
    /// destination active content를 교체하기 전에 close/pin/Collection/AI pending을 busy로 보존하는지 검증한다.
    /// - 검증 내용: destination 네 pending category의 typed rejection과 complete source/target snapshot equality
    /// - 사전 조건: destination의 valid active tab에 category별 pending state 하나만 설정
    /// - 기대 결과: 각 category가 정확히 reject되고 어떤 state도 변경되지 않음
    func testPreflightRejectsAllDestinationPendingCategoriesWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "moved")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/moved")],
            active: movedID,
        )
        let targetID = ContentTabID(rawValue: "target")
        var busyTarget = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetID, path: "/target")],
            active: targetID,
        )
        busyTarget.pendingContentTabClose = PendingContentTabClose(tabID: targetID)
        try assertRejected(.ineligible(.pendingContentTabClose), source: source, target: busyTarget, tabID: movedID)

        busyTarget = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetID, path: "/target")],
            active: targetID,
        )
        busyTarget.contentTabs.pendingPinnedRecordIDs = [targetID]
        try assertRejected(
            .ineligible(.pendingPinnedRecordPersistence),
            source: source,
            target: busyTarget,
            tabID: movedID,
        )

        busyTarget = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetID, path: "/target")],
            active: targetID,
        )
        busyTarget.content.collection.isSaving = true
        busyTarget.tabContentStates[targetID] = busyTarget.content
        try assertRejected(.ineligible(.pendingCollectionOperation), source: source, target: busyTarget, tabID: movedID)

        busyTarget = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetID, path: "/target")],
            active: targetID,
        )
        busyTarget.content.aiChat.streamingAssistantDraft = "streaming"
        busyTarget.tabContentStates[targetID] = busyTarget.content
        try assertRejected(.ineligible(.pendingAiChatOperation), source: source, target: busyTarget, tabID: movedID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: destination window-level busy는 preflight에서 거절한다.
    /// target work-unit projection 전에 close와 Undo lifecycle gate를 동일하게 적용하는지 검증한다.
    /// - 검증 내용: target isClosing/active undoRedoPhase/pending move rejection과 source/target snapshot equality
    /// - 사전 조건: valid source/target에서 target만 closing, Undo invoking, 또는 outgoing move 상태다.
    /// - 기대 결과: 세 preflight 모두 success token을 만들지 않고 양 window state가 변경되지 않는다.
    func testPreflightRejectsTargetWindowBusyBeforeProjectionWithoutMutation() {
        let movedID = ContentTabID(rawValue: "window-busy-source")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/window-busy/source")],
            active: movedID,
        )
        let targetID = ContentTabID(rawValue: "window-busy-target")
        let target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetID, path: "/window-busy/target")],
            active: targetID,
        )
        let requestID = UUID(uuid: (45, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        var closingTarget = target
        closingTarget.isClosing = true
        var undoBusyTarget = target
        undoBusyTarget.undoRedoPhase = .invoking(requestID: requestID, direction: .undo)
        let pendingRequest = ContentTabMoveRequest(
            requestID: UUID(uuid: (45, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
            sourceWindowID: Fixture.targetWindowID,
            tabID: targetID,
            targetWindowID: UUID(uuid: (45, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)),
        )
        var pendingMoveTarget = target
        pendingMoveTarget.pendingContentTabMove = .init(request: pendingRequest, lifecycle: .inFlight)
        pendingMoveTarget.sidebar.pendingContentTabMoveRequest = pendingRequest

        for busyTarget in [closingTarget, undoBusyTarget, pendingMoveTarget] {
            let sourceBefore = source
            let targetBefore = busyTarget
            let result = ContentTabTransfer.preflight(source: source, target: busyTarget, tabID: movedID)
            XCTAssertEqual(result.rejection, .ineligible(.windowBusy))
            XCTAssertEqual(source, sourceBefore)
            XCTAssertEqual(busyTarget, targetBefore)
        }
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: destination의 ambiguous background AI provenance를
    /// reject한다.
    /// passive projection 제거를 포함한 어떤 mutation보다 window-wide provenance 검증이 먼저 실행되는지 검증한다.
    /// - 검증 내용: 동일 processing session의 open owner 2개, unrelated source transfer rejection, full snapshot equality
    /// - 사전 조건: destination의 두 directory tab이 같은 background AI session을 소유한다.
    /// - 기대 결과: `.ineligible(.malformedOwnership)`이고 source/target 전체 state가 변경되지 않는다.
    func testPreflightRejectsAmbiguousDestinationBackgroundAiProvenanceWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "destination-provenance-source")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/source")],
            active: movedID,
        )
        let firstID = ContentTabID(rawValue: "destination-provenance-first")
        let secondID = ContentTabID(rawValue: "destination-provenance-second")
        let sessionID = AiChatSessionID(
            rawValue: UUID(uuid: (90, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)),
        )
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(firstID, path: "/target/first"),
                Fixture.tab(secondID, path: "/target/second"),
            ],
            active: firstID,
        )
        target.tabContentStates[firstID]?.aiChat.sessionID = sessionID
        target.tabContentStates[secondID]?.aiChat.sessionID = sessionID
        target.content = try XCTUnwrap(target.tabContentStates[firstID])
        var background = FileManagerContentState.initialContent(
            for: .aiChat(sessionID: sessionID.rawValue.uuidString),
        )
        background.aiChat.streamingAssistantDraft = "processing"
        target.backgroundAiChatStates[sessionID] = background

        try assertRejected(
            .ineligible(.malformedOwnership),
            source: source,
            target: target,
            tabID: movedID,
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: AI anchor collision은 cache session이 없어도 reject한다.
    /// lifecycle anchor가 같은 두 work unit이 target에 공존하지 않도록 fail-closed인지 검증한다.
    /// - 검증 내용: ContentTabPageAnchor.aiChat session key collision
    /// - 사전 조건: source/target AI tab이 같은 anchor string을 갖고 cache sessionID는 nil
    /// - 기대 결과: targetSessionCollision이고 양 state snapshot 불변
    func testPreflightRejectsAiAnchorCollisionWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "moved")
        let anchorSession = Fixture.sessionUUID.uuidString
        let sourceTab = Fixture.aiTab(movedID, sessionID: anchorSession)
        let targetID = ContentTabID(rawValue: "anchor-target")
        let targetTab = Fixture.aiTab(targetID, sessionID: anchorSession)
        let source = Fixture.window(windowID: Fixture.sourceWindowID, tabs: [sourceTab], active: movedID)
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [targetTab], active: targetID)

        try assertRejected(.targetSessionCollision, source: source, target: target, tabID: movedID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: app-global passive pinned projection을 source work
    /// unit으로 승계한다.
    /// 동일 stable ID projection 충돌을 안전하게 해소하고 source 재삽입을 suppression하는 계약을 검증한다.
    /// - 검증 내용: stale durable metadata 허용, target passive projection 교체, source suppression과 global sync
    /// - 사전 조건: 양 window에 같은 pinned ID가 있고 target은 passive projection, source는 runtime anchor가 변경됨
    /// - 기대 결과: target은 source exact work unit 하나를 소유하고 source에는 global sync 후에도 tab이 재삽입되지 않음
    func testTransferAdoptsPassiveGlobalPinnedProjectionAndSuppressesSourceReinsertion() throws {
        let tabID = ContentTabID(rawValue: "global-pinned")
        let projectedTab = Fixture.tab(tabID, path: "/pinned", pinned: true)
        let runtimeTab = Fixture.tab(tabID, path: "/runtime", pinned: true)
        let record = Fixture.pinRecord(for: projectedTab)
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [runtimeTab],
            active: tabID,
        )
        source.contentTabs.pinnedRecords[tabID] = record
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [projectedTab],
            active: tabID,
        )
        target.contentTabs.pinnedRecords[tabID] = record

        let result = ContentTabTransfer.transfer(source: source, target: target, tabID: tabID)
        let postCommit = try result.closeSourceWindowPostCommit()

        XCTAssertEqual(postCommit.target.contentTabs.tabs.map(\.id), [tabID])
        XCTAssertEqual(postCommit.target.contentTabs.tabs[id: tabID], runtimeTab)
        XCTAssertEqual(postCommit.target.contentTabs.pinnedRecords[tabID], record)
        XCTAssertEqual(postCommit.target.content.navigation.currentPath, "/runtime")
        XCTAssertTrue(postCommit.source.suppressedPinnedTabIDs.contains(tabID))

        let restored = ContentTabState(
            tabs: [projectedTab],
            activeTabID: tabID,
            pinnedRecords: [tabID: record],
        )
        var resynchronizedSource = postCommit.source
        resynchronizedSource.applyPinnedContentTabs(restored)
        XCTAssertNil(resynchronizedSource.contentTabs.tabs[id: tabID])
        XCTAssertTrue(resynchronizedSource.suppressedPinnedTabIDs.contains(tabID))

        resynchronizedSource.applyPinnedContentTabs(ContentTabState())
        XCTAssertFalse(resynchronizedSource.suppressedPinnedTabIDs.contains(tabID))
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: 의미 상태가 있는 same-ID pinned target은 교체하지 않는다.
    /// passive projection 이외의 target runtime을 source 이동이 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: target pending selection이 있는 same-ID projection의 atomic rejection
    /// - 사전 조건: 양 window에 같은 pinned ID가 있고 target Content에 의미 있는 selection intent가 있음
    /// - 기대 결과: targetTabCollision이며 source/target 전체 snapshot은 불변
    func testTransferRejectsDivergentGlobalPinnedProjectionWithoutMutation() throws {
        let tabID = ContentTabID(rawValue: "global-pinned-divergent")
        let tab = Fixture.tab(tabID, path: "/pinned", pinned: true)
        let record = Fixture.pinRecord(for: tab)
        var source = Fixture.window(windowID: Fixture.sourceWindowID, tabs: [tab], active: tabID)
        source.contentTabs.pinnedRecords[tabID] = record
        var target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [tab], active: tabID)
        target.contentTabs.pinnedRecords[tabID] = record
        target.content.pendingSelectEntryID = "/pinned/selected.txt"
        target.tabContentStates[tabID] = target.content

        try assertRejected(.targetTabCollision, source: source, target: target, tabID: tabID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: navigation 또는 Composer 의미 상태가 있는 pinned
    /// projection은 passive로 간주하지 않는다.
    /// source 이동이 target의 보이지 않는 탐색·검색 상태를 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: navigation path와 Composer collection context가 다른 same-ID target의 atomic rejection
    /// - 사전 조건: 양 window에 같은 pinned ID가 있고 target projection에 각각 탐색 또는 Composer 상태가 있음
    /// - 기대 결과: 두 경우 모두 targetTabCollision이며 source/target snapshot은 불변
    func testTransferRejectsPinnedProjectionWithNavigationOrComposerStateWithoutMutation() throws {
        let tabID = ContentTabID(rawValue: "global-pinned-semantic-state")
        let tab = Fixture.tab(tabID, path: "/pinned", pinned: true)
        let record = Fixture.pinRecord(for: tab)
        var source = Fixture.window(windowID: Fixture.sourceWindowID, tabs: [tab], active: tabID)
        source.contentTabs.pinnedRecords[tabID] = record

        var navigationTarget = Fixture.window(windowID: Fixture.targetWindowID, tabs: [tab], active: tabID)
        navigationTarget.contentTabs.pinnedRecords[tabID] = record
        navigationTarget.content.navigation.seedInitialFolderPath("/pinned/navigated")
        navigationTarget.tabContentStates[tabID] = navigationTarget.content
        try assertRejected(.targetTabCollision, source: source, target: navigationTarget, tabID: tabID)

        var composerTarget = Fixture.window(windowID: Fixture.targetWindowID, tabs: [tab], active: tabID)
        composerTarget.contentTabs.pinnedRecords[tabID] = record
        composerTarget.content.composer.collectionContext = CollectionContext(
            query: "kind:pdf",
            scopes: [],
            conditions: [],
        )
        composerTarget.tabContentStates[tabID] = composerTarget.content
        try assertRejected(.targetTabCollision, source: source, target: composerTarget, tabID: tabID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: Content/Inspector AI의 표시 의미 상태가 있는 pinned
    /// projection은 passive로 간주하지 않는다.
    /// source 이동이 target의 session 검색 또는 Inspector draft를 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: Content session-list query와 Inspector draft의 atomic rejection
    /// - 사전 조건: 양 window에 같은 pinned ID가 있고 target의 Content 또는 Inspector AI에 의미 상태가 있음
    /// - 기대 결과: 두 경우 모두 targetTabCollision이며 source/target snapshot은 불변
    func testTransferRejectsPinnedProjectionWithContentOrInspectorAiStateWithoutMutation() throws {
        let tabID = ContentTabID(rawValue: "global-pinned-ai-state")
        let tab = Fixture.tab(tabID, path: "/pinned", pinned: true)
        let record = Fixture.pinRecord(for: tab)
        var source = Fixture.window(windowID: Fixture.sourceWindowID, tabs: [tab], active: tabID)
        source.contentTabs.pinnedRecords[tabID] = record

        var contentAiTarget = Fixture.window(windowID: Fixture.targetWindowID, tabs: [tab], active: tabID)
        contentAiTarget.contentTabs.pinnedRecords[tabID] = record
        contentAiTarget.content.aiChat.sessionList.updateQuery("important session")
        contentAiTarget.tabContentStates[tabID] = contentAiTarget.content
        try assertRejected(.targetTabCollision, source: source, target: contentAiTarget, tabID: tabID)

        var inspectorAiTarget = Fixture.window(windowID: Fixture.targetWindowID, tabs: [tab], active: tabID)
        inspectorAiTarget.contentTabs.pinnedRecords[tabID] = record
        inspectorAiTarget.inspector.aiChat.draftText = "preserve inspector draft"
        inspectorAiTarget.tabInspectorStates[tabID] = inspectorAiTarget.inspector.tabSnapshot()
        try assertRejected(.targetTabCollision, source: source, target: inspectorAiTarget, tabID: tabID)
    }

    func testPreflightRejectsMovedSourceComposerTransientWorkWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "transient-source-composer")
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        let mutations: [(inout FileManagerWindowState) -> Void] = [
            { state in
                state.content.composer.activeSearchRequestID = UUID()
                state.content.composer.isLoadingSearch = true
                state.content.composer.queryRenderPhase = .searching
            },
            { state in
                state.content.composer.activeFiltersRequestID = UUID()
                state.content.composer.isLoadingFilters = true
            },
            { state in
                state.content.composer.activeFiltersRequestID = UUID()
                state.content.composer.isFilteringInFlight = true
            },
            { state in
                state.content.composer.queryRenderPhase = .chipsAppliedPendingList
            },
        ]

        for mutate in mutations {
            var source = Fixture.window(
                windowID: Fixture.sourceWindowID,
                tabs: [Fixture.tab(movedID, path: "/transient/source/composer")],
                active: movedID,
            )
            mutate(&source)
            source.tabContentStates[movedID] = source.content
            try assertRejected(
                .ineligible(.pendingCollectionOperation),
                source: source,
                target: target,
                tabID: movedID,
            )
        }
    }

    func testPreflightRejectsMovedSourceContentAndInspectorAiTransientWorkWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "transient-source-ai")
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        let mutations: [(inout FileManagerWindowState) -> Void] = [
            { $0.content.aiChat.modelListRequestID = UUID() },
            { $0.content.aiChat.modelListPendingProviders = [.openai] },
            { $0.content.aiChat.modelListState = .loading },
            { $0.content.aiChat.sessionList.isLoading = true },
            { $0.inspector.aiChat.modelListState = .loading },
            { $0.inspector.aiChat.sessionList.isLoading = true },
        ]

        for mutate in mutations {
            var source = Fixture.window(
                windowID: Fixture.sourceWindowID,
                tabs: [Fixture.tab(movedID, path: "/transient/source/ai")],
                active: movedID,
            )
            mutate(&source)
            source.tabContentStates[movedID] = source.content
            source.tabInspectorStates[movedID] = source.inspector.tabSnapshot()
            try assertRejected(
                .ineligible(.pendingAiChatOperation),
                source: source,
                target: target,
                tabID: movedID,
            )
        }
    }

    func testPreflightRejectsDestinationOutgoingComposerAndAiTransientWorkWithoutMutation() throws {
        let movedID = ContentTabID(rawValue: "transient-target-source")
        let targetID = ContentTabID(rawValue: "transient-target-active")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/transient/target/source")],
            active: movedID,
        )
        let cases: [(
            ContentTabTransfer.Rejection,
            (inout FileManagerWindowState) -> Void,
        )] = [
            (.ineligible(.pendingCollectionOperation), { state in
                state.content.composer.activeSearchRequestID = UUID()
                state.content.composer.isLoadingSearch = true
            }),
            (.ineligible(.pendingCollectionOperation), { state in
                state.content.composer.activeFiltersRequestID = UUID()
                state.content.composer.isFilteringInFlight = true
            }),
            (.ineligible(.pendingAiChatOperation), { $0.content.aiChat.modelListRequestID = UUID() }),
            (.ineligible(.pendingAiChatOperation), { $0.content.aiChat.sessionList.isLoading = true }),
            (.ineligible(.pendingAiChatOperation), { $0.inspector.aiChat.modelListPendingProviders = [.anthropic] }),
            (.ineligible(.pendingAiChatOperation), { $0.inspector.aiChat.sessionList.isLoading = true }),
        ]

        for (expected, mutate) in cases {
            var target = Fixture.window(
                windowID: Fixture.targetWindowID,
                tabs: [Fixture.tab(targetID, path: "/transient/target/active")],
                active: targetID,
            )
            mutate(&target)
            target.tabContentStates[targetID] = target.content
            target.tabInspectorStates[targetID] = target.inspector.tabSnapshot()
            try assertRejected(expected, source: source, target: target, tabID: movedID)
        }
    }

    func testPreflightAllowsSettledStateAndIgnoresUnrelatedActiveOrDestinationInactiveTransientWork() throws {
        let movedID = ContentTabID(rawValue: "transient-negative-moved")
        let sourceActiveID = ContentTabID(rawValue: "transient-negative-source-active")
        let targetActiveID = ContentTabID(rawValue: "transient-negative-target-active")
        let targetInactiveID = ContentTabID(rawValue: "transient-negative-target-inactive")
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(sourceActiveID, path: "/negative/source/active"),
                Fixture.tab(movedID, path: "/negative/source/moved"),
            ],
            active: sourceActiveID,
        )
        source.content.composer.activeSearchRequestID = UUID()
        source.content.composer.isLoadingSearch = true
        source.content.aiChat.modelListState = .loading
        source.inspector.aiChat.sessionList.isLoading = true
        source.tabContentStates[sourceActiveID] = source.content
        source.tabInspectorStates[sourceActiveID] = source.inspector.tabSnapshot()
        source.tabContentStates[movedID]?.composer.text = "settled query"
        source.tabContentStates[movedID]?.composer.pendingSearchQuery = "settled query"
        source.tabContentStates[movedID]?.composer.lastAcceptedSearchRequestID = UUID()
        source.tabContentStates[movedID]?.composer.lastAcceptedFiltersRequestID = UUID()
        source.tabContentStates[movedID]?.composer.queryRenderPhase = .listApplied
        source.tabContentStates[movedID]?.aiChat.modelListState = .empty
        source.tabContentStates[movedID]?.aiChat.sessionList.updateQuery("settled history")

        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(targetActiveID, path: "/negative/target/active"),
                Fixture.tab(targetInactiveID, path: "/negative/target/inactive"),
            ],
            active: targetActiveID,
        )
        target.content.composer.text = "settled target query"
        target.content.composer.lastAcceptedSearchRequestID = UUID()
        target.content.composer.queryRenderPhase = .listApplied
        target.content.aiChat.modelListState = .empty
        target.content.aiChat.sessionList.updateQuery("settled target history")
        target.tabContentStates[targetActiveID] = target.content
        target.tabContentStates[targetInactiveID]?.composer.activeFiltersRequestID = UUID()
        target.tabContentStates[targetInactiveID]?.composer.isFilteringInFlight = true
        target.tabContentStates[targetInactiveID]?.aiChat.modelListState = .loading
        target.tabContentStates[targetInactiveID]?.aiChat.sessionList.isLoading = true
        target.tabInspectorStates[targetInactiveID]?.aiChat.modelListRequestID = UUID()
        target.tabInspectorStates[targetInactiveID]?.aiChat.sessionList.isLoading = true

        let result = ContentTabTransfer.transfer(source: source, target: target, tabID: movedID)
        XCTAssertNoThrow(try result.movedPostCommit())
    }

    func testPreflightCapturesExactSourceAndTargetOutgoingOwnerProvenance() throws {
        let movedID = ContentTabID(rawValue: "owner-source-moved")
        let fallbackID = ContentTabID(rawValue: "owner-source-fallback")
        let targetID = ContentTabID(rawValue: "owner-target-outgoing")
        let sourceLoadingWindowID = UUID(uuid: (70, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        let sourceLoadingOwnerID = UUID(uuid: (70, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
        let sourceComposerOwnerID = UUID(uuid: (70, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
        let targetLoadingWindowID = UUID(uuid: (70, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))
        let targetLoadingOwnerID = UUID(uuid: (70, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5))
        let targetComposerOwnerID = UUID(uuid: (70, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6))
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(movedID, path: "/owner/source/moved"),
                Fixture.tab(fallbackID, path: "/owner/source/fallback"),
            ],
            active: movedID,
            previous: fallbackID,
        )
        source.content.entryViewLayout.entryOperations.windowID = sourceLoadingWindowID
        source.content.entryViewLayout.entryOperations.loadingCancellationOwnerID = sourceLoadingOwnerID
        source.content.composer.cancellationOwnerID = sourceComposerOwnerID
        source.tabContentStates[movedID] = source.content
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetID, path: "/owner/target/outgoing")],
            active: targetID,
        )
        target.content.entryViewLayout.entryOperations.windowID = targetLoadingWindowID
        target.content.entryViewLayout.entryOperations.loadingCancellationOwnerID = targetLoadingOwnerID
        target.content.composer.cancellationOwnerID = targetComposerOwnerID
        target.tabContentStates[targetID] = target.content
        let sourceBefore = source
        let targetBefore = target

        let token = try ContentTabTransfer.preflight(
            source: source,
            target: target,
            tabID: movedID,
        )
        .successToken()

        XCTAssertEqual(source, sourceBefore)
        XCTAssertEqual(target, targetBefore)
        XCTAssertEqual(token.sourceOutgoingOwner, .init(
            tabID: movedID,
            loadingWindowID: sourceLoadingWindowID,
            loadingOwnerID: sourceLoadingOwnerID,
            composerOwnerID: sourceComposerOwnerID,
            canCancelLoadingExclusively: true,
            canCancelComposerExclusively: true,
        ))
        XCTAssertEqual(token.targetOutgoingOwner, .init(
            tabID: targetID,
            loadingWindowID: targetLoadingWindowID,
            loadingOwnerID: targetLoadingOwnerID,
            composerOwnerID: targetComposerOwnerID,
            canCancelLoadingExclusively: true,
            canCancelComposerExclusively: true,
        ))
        let postCommit = try ContentTabTransfer.apply(token).movedPostCommit()
        XCTAssertEqual(postCommit.rebind.sourceOutgoingOwner, token.sourceOutgoingOwner)
        XCTAssertEqual(postCommit.rebind.targetOutgoingOwner, token.targetOutgoingOwner)
    }

    func testPreflightDoesNotMarkSharedSiblingOwnersSafeForCancellation() throws {
        let movedID = ContentTabID(rawValue: "shared-owner-moved")
        let sourceSiblingID = ContentTabID(rawValue: "shared-owner-source-sibling")
        let targetID = ContentTabID(rawValue: "shared-owner-target")
        let targetSiblingID = ContentTabID(rawValue: "shared-owner-target-sibling")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(movedID, path: "/shared/source/moved"),
                Fixture.tab(sourceSiblingID, path: "/shared/source/sibling"),
            ],
            active: movedID,
        )
        let target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(targetID, path: "/shared/target/outgoing"),
                Fixture.tab(targetSiblingID, path: "/shared/target/sibling"),
            ],
            active: targetID,
        )

        let token = try ContentTabTransfer.preflight(
            source: source,
            target: target,
            tabID: movedID,
        )
        .successToken()

        XCTAssertFalse(token.sourceOutgoingOwner.canCancelLoadingExclusively)
        XCTAssertFalse(token.sourceOutgoingOwner.canCancelComposerExclusively)
        XCTAssertFalse(try XCTUnwrap(token.targetOutgoingOwner).canCancelLoadingExclusively)
        XCTAssertFalse(try XCTUnwrap(token.targetOutgoingOwner).canCancelComposerExclusively)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: mixed domain batch는 frozen 순서로 이동한다.
    /// 비연속 pinned/unpinned 선택의 work unit과 immutable projection/lifecycle token을 검증한다.
    /// - 검증 내용: frozen WorkUnit 순서, domain별 append, snapshot fingerprint, apply projection
    /// - 사전 조건: source에 비연속 mixed 선택, target에 기존 pinned/unpinned tab이 있다.
    /// - 기대 결과: 각 domain 상대 순서와 owner identity가 보존되고 apply는 token projection을 그대로 반환한다.
    func testBatchPreflightPreservesMixedDomainFrozenOrderAndProjectsImmutableToken() throws {
        let scenario = MixedBatchTransferScenario()
        let sourceBefore = scenario.source
        let targetBefore = scenario.target
        let preflight = ContentTabTransfer.preflight(
            source: scenario.source,
            target: scenario.target,
            orderedTabIDs: scenario.orderedIDs,
            primaryTabID: scenario.unpinnedID,
        )
        let token = try preflight.successToken()

        XCTAssertEqual(scenario.source, sourceBefore)
        XCTAssertEqual(scenario.target, targetBefore)
        XCTAssertEqual(token.workUnits.map(\.item.id), scenario.orderedIDs)
        XCTAssertEqual(token.workUnits.map(\.content.pendingSelectEntryID), [
            "pinned-second-owner",
            "pinned-first-owner",
            "unpinned-owner",
        ])
        XCTAssertEqual(token.sourceFingerprint.windowID, Fixture.sourceWindowID)
        XCTAssertEqual(token.sourceFingerprint.tabIDs, Array(sourceBefore.contentTabs.tabs.ids))
        XCTAssertEqual(token.targetFingerprint.windowID, Fixture.targetWindowID)
        XCTAssertEqual(token.targetFingerprint.tabIDs, Array(targetBefore.contentTabs.tabs.ids))
        XCTAssertEqual(token.rebindIntents.map(\.tabID), scenario.orderedIDs)
        XCTAssertEqual(
            Array(token.projectedTarget.contentTabs.tabs.ids),
            scenario.expectedTargetIDs,
        )
        XCTAssertEqual(
            token.projectedTarget.contentTabs.tabs.filter(\.isPinned).map(\.id),
            [scenario.targetPinnedID, scenario.pinnedSecondID, scenario.pinnedFirstID],
        )
        XCTAssertEqual(
            token.projectedTarget.contentTabs.tabs.filter { !$0.isPinned }.map(\.id),
            [scenario.targetUnpinnedID, scenario.unpinnedID],
        )
        XCTAssertEqual(token.projectedTarget.contentTabs.selectedTabIDs, Set(scenario.orderedIDs))
        XCTAssertEqual(token.projectedTarget.contentTabs.activeTabID, scenario.unpinnedID)
        XCTAssertEqual(token.projectedTarget.contentTabs.selectionAnchorID, scenario.unpinnedID)
        XCTAssertEqual(token.projectedSource.contentTabs.activeTabID, scenario.survivorID)
        XCTAssertEqual(token.projectedSource.contentTabs.selectedTabIDs, [scenario.survivorID])
        XCTAssertEqual(token.projectedSource.contentTabs.selectionAnchorID, scenario.survivorID)

        let postCommit = try ContentTabTransfer.apply(token).movedPostCommit()
        XCTAssertEqual(postCommit.source, token.projectedSource)
        XCTAssertEqual(postCommit.target, token.projectedTarget)
        XCTAssertEqual(postCommit.rebinds, token.rebindIntents)
        XCTAssertEqual(postCommit.teardownIntents, token.teardownIntents)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: shared lifecycle owner는 한 번만 teardown한다.
    /// loading/composer scope가 같은 두 moved tab에서 frozen 첫 owner가 token intent를 소유하는지 검증한다.
    /// - 검증 내용: loading/composer scope별 ordered-unique teardown과 primary compatibility owner
    /// - 사전 조건: 같은 source window owner를 공유하는 두 tab을 역순 frozen batch로 모두 이동한다.
    /// - 기대 결과: teardown intent는 하나이고 첫 frozen tab이 scope correlation을 소유한다.
    func testBatchDeduplicatesSharedTeardownScopesByFirstFrozenOwner() throws {
        let primaryID = ContentTabID(rawValue: "batch-shared-primary")
        let firstFrozenID = ContentTabID(rawValue: "batch-shared-first-frozen")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(primaryID, path: "/batch/shared-primary"),
                Fixture.tab(firstFrozenID, path: "/batch/shared-first-frozen"),
            ],
            active: primaryID,
        )
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)

        let preflight = ContentTabTransfer.preflight(
            source: source,
            target: target,
            orderedTabIDs: [firstFrozenID, primaryID],
            primaryTabID: primaryID,
        )
        let token = try preflight.successToken()

        let teardown = try XCTUnwrap(token.teardownIntents.first)
        XCTAssertEqual(token.teardownIntents.count, 1)
        XCTAssertEqual(teardown.tabID, firstFrozenID)
        XCTAssertEqual(teardown.loadingScope?.windowID, Fixture.sourceWindowID)
        XCTAssertEqual(teardown.loadingScope?.ownerID, Fixture.sourceWindowID)
        XCTAssertEqual(teardown.composerScope?.ownerID, Fixture.sourceWindowID)
        XCTAssertEqual(token.sourceOutgoingOwner.tabID, primaryID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: nil composer owner는 teardown scope가 아니다.
    /// composer owner가 없는 moved tab이 가짜 nil scope를 만들지 않는지 검증한다.
    /// - 검증 내용: valid loading teardown 유지와 nil composer teardown 제거
    /// - 사전 조건: source의 유일한 moved tab은 loading owner만 있고 composer owner는 nil이다.
    /// - 기대 결과: teardown intent에는 loading scope만 있고 composer scope는 없다.
    func testBatchOmitsComposerTeardownScopeWhenOwnerIsNil() throws {
        let movedID = ContentTabID(rawValue: "batch-nil-composer")
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/batch/nil-composer")],
            active: movedID,
        )
        source.content.composer.cancellationOwnerID = nil
        source.tabContentStates[movedID] = source.content
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        let preflight = ContentTabTransfer.preflight(
            source: source,
            target: target,
            orderedTabIDs: [movedID],
            primaryTabID: movedID,
        )

        let teardown = try XCTUnwrap(preflight.successToken().teardownIntents.first)
        XCTAssertEqual(teardown.loadingScope?.windowID, Fixture.sourceWindowID)
        XCTAssertEqual(teardown.loadingScope?.ownerID, Fixture.sourceWindowID)
        XCTAssertNil(teardown.composerScope)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: batch 이동 후 surviving source 상태를 보존한다.
    /// 이동하지 않은 active, selection, anchor가 batch projection에서 흔들리지 않는지 검증한다.
    /// - 검증 내용: active survivor와 surviving selected IDs/anchor 보존
    /// - 사전 조건: active와 selection anchor는 source에 남고 선택 멤버 하나만 이동한다.
    /// - 기대 결과: source active/selection/anchor는 원래 surviving 값으로 유지된다.
    func testBatchKeepsSurvivingSourceActiveSelectionAndAnchor() throws {
        let anchorID = ContentTabID(rawValue: "batch-source-anchor")
        let movedID = ContentTabID(rawValue: "batch-source-moved")
        let activeID = ContentTabID(rawValue: "batch-source-active")
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(anchorID, path: "/batch/anchor"),
                Fixture.tab(movedID, path: "/batch/moved"),
                Fixture.tab(activeID, path: "/batch/active"),
            ],
            active: activeID,
        )
        source.contentTabs.selectedTabIDs = [anchorID, movedID]
        source.contentTabs.selectionAnchorID = anchorID
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)

        let postCommit = try batchPostCommit(
            source: source,
            target: target,
            orderedTabIDs: [movedID],
            primaryTabID: movedID,
        )

        XCTAssertEqual(postCommit.source.contentTabs.activeTabID, activeID)
        XCTAssertEqual(postCommit.source.contentTabs.selectedTabIDs, [anchorID])
        XCTAssertEqual(postCommit.source.contentTabs.selectionAnchorID, anchorID)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: batch source fallback은 deterministic하다.
    /// active가 이동될 때 previous, 오른쪽, 왼쪽 survivor 우선순위를 검증한다.
    /// - 검증 내용: previous → first right → last left fallback과 singleton selection/anchor
    /// - 사전 조건: 세 source가 각각 valid previous, right-only, left-only survivor를 가진다.
    /// - 기대 결과: 각 source가 정의된 우선순위의 active/selection/anchor를 선택한다.
    func testBatchChoosesPreviousThenRightThenLeftSourceFallback() throws {
        let leftID = ContentTabID(rawValue: "batch-fallback-left")
        let movedID = ContentTabID(rawValue: "batch-fallback-moved")
        let rightID = ContentTabID(rawValue: "batch-fallback-right")
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        let cases: [(FileManagerWindowState, ContentTabID)] = [
            (Fixture.window(
                windowID: Fixture.sourceWindowID,
                tabs: [
                    Fixture.tab(leftID, path: "/batch/previous-left"),
                    Fixture.tab(movedID, path: "/batch/previous-moved"),
                    Fixture.tab(rightID, path: "/batch/previous-right"),
                ],
                active: movedID,
                previous: leftID,
            ), leftID),
            (Fixture.window(
                windowID: Fixture.sourceWindowID,
                tabs: [
                    Fixture.tab(leftID, path: "/batch/right-left"),
                    Fixture.tab(movedID, path: "/batch/right-moved"),
                    Fixture.tab(rightID, path: "/batch/right-right"),
                ],
                active: movedID,
            ), rightID),
            (Fixture.window(
                windowID: Fixture.sourceWindowID,
                tabs: [
                    Fixture.tab(leftID, path: "/batch/left-left"),
                    Fixture.tab(movedID, path: "/batch/left-moved"),
                ],
                active: movedID,
            ), leftID),
        ]

        for (source, expectedFallbackID) in cases {
            let result = try batchPostCommit(
                source: source,
                target: target,
                orderedTabIDs: [movedID],
                primaryTabID: movedID,
            )
            XCTAssertEqual(result.source.contentTabs.activeTabID, expectedFallbackID)
            XCTAssertEqual(result.source.contentTabs.selectedTabIDs, [expectedFallbackID])
            XCTAssertEqual(result.source.contentTabs.selectionAnchorID, expectedFallbackID)
        }
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: 전체 batch 이동은 empty source로 종료한다.
    /// source-empty token과 close disposition이 fallback이나 selection을 만들지 않는지 검증한다.
    /// - 검증 내용: sourceIsEmpty, nil active/previous/anchor, empty selection, closeSourceWindow
    /// - 사전 조건: source의 두 tab 모두 이동하고 target에는 기존 tab이 있다.
    /// - 기대 결과: source-empty가 한 번의 close disposition으로 표현되고 target commit은 완성된다.
    func testBatchEmptiesSourceWithoutFallbackAndClosesOnce() throws {
        let firstID = ContentTabID(rawValue: "batch-empty-first")
        let secondID = ContentTabID(rawValue: "batch-empty-second")
        let targetID = ContentTabID(rawValue: "batch-empty-target")
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(firstID, path: "/batch/empty-first"),
                Fixture.tab(secondID, path: "/batch/empty-second"),
            ],
            active: firstID,
            previous: secondID,
        )
        source.contentTabs.selectedTabIDs = [firstID, secondID]
        source.contentTabs.selectionAnchorID = firstID
        let target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetID, path: "/batch/empty-target")],
            active: targetID,
        )

        let preflight = ContentTabTransfer.preflight(
            source: source,
            target: target,
            orderedTabIDs: [secondID, firstID],
            primaryTabID: firstID,
        )
        let token = try preflight.successToken()

        XCTAssertTrue(token.sourceIsEmpty)
        XCTAssertTrue(token.projectedSource.contentTabs.tabs.isEmpty)
        XCTAssertNil(token.projectedSource.contentTabs.activeTabID)
        XCTAssertNil(token.projectedSource.contentTabs.previousActiveTabID)
        XCTAssertTrue(token.projectedSource.contentTabs.selectedTabIDs.isEmpty)
        XCTAssertNil(token.projectedSource.contentTabs.selectionAnchorID)
        let postCommit = try ContentTabTransfer.apply(token).closeSourceWindowPostCommit()
        XCTAssertEqual(postCommit.source, token.projectedSource)
        XCTAssertEqual(postCommit.target, token.projectedTarget)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: target selection은 moved batch로 교체한다.
    /// 기존 target selection을 병합하지 않고 primary를 active/anchor로 사용하는지 검증한다.
    /// - 검증 내용: moved-only target selection, primary active/anchor, prior active previous
    /// - 사전 조건: source 두 tab과 별도 selection을 가진 target 두 tab이 있다.
    /// - 기대 결과: target selection은 정확히 moved IDs이고 primary가 active/anchor가 된다.
    func testBatchReplacesTargetSelectionWithMovedIDsAndPrimary() throws {
        let firstID = ContentTabID(rawValue: "batch-selection-first")
        let primaryID = ContentTabID(rawValue: "batch-selection-primary")
        let targetActiveID = ContentTabID(rawValue: "batch-selection-target-active")
        let targetSelectedID = ContentTabID(rawValue: "batch-selection-target-selected")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(firstID, path: "/batch/selection-first"),
                Fixture.tab(primaryID, path: "/batch/selection-primary"),
            ],
            active: firstID,
        )
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(targetActiveID, path: "/batch/target-active"),
                Fixture.tab(targetSelectedID, path: "/batch/target-selected"),
            ],
            active: targetActiveID,
        )
        target.contentTabs.selectedTabIDs = [targetActiveID, targetSelectedID]
        target.contentTabs.selectionAnchorID = targetSelectedID

        let postCommit = try batchPostCommit(
            source: source,
            target: target,
            orderedTabIDs: [firstID, primaryID],
            primaryTabID: primaryID,
            closesSource: true,
        )

        XCTAssertEqual(postCommit.target.contentTabs.selectedTabIDs, [firstID, primaryID])
        XCTAssertEqual(postCommit.target.contentTabs.activeTabID, primaryID)
        XCTAssertEqual(postCommit.target.contentTabs.selectionAnchorID, primaryID)
        XCTAssertEqual(postCommit.target.contentTabs.previousActiveTabID, targetActiveID)
        XCTAssertFalse(postCommit.target.contentTabs.selectedTabIDs.contains(targetSelectedID))
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: passive replacements를 누적 capacity로 계산한다.
    /// full target의 두 passive pinned slot을 batch 전체에서 함께 교체할 수 있는지 검증한다.
    /// - 검증 내용: effective capacity, 두 passive projection 교체, final maxTabs 유지
    /// - 사전 조건: target은 maxTabs이고 두 pinned ID는 replaceable passive projection이다.
    /// - 기대 결과: capacity rejection 없이 두 source runtime work unit이 target projection을 교체한다.
    func testBatchUsesAllPassivePinnedReplacementsForCapacity() throws {
        let firstID = ContentTabID(rawValue: "batch-capacity-first")
        let secondID = ContentTabID(rawValue: "batch-capacity-second")
        let firstProjection = Fixture.tab(firstID, path: "/batch/passive-first", pinned: true)
        let secondProjection = Fixture.tab(secondID, path: "/batch/passive-second", pinned: true)
        let firstRuntime = Fixture.tab(firstID, path: "/batch/runtime-first", pinned: true)
        let secondRuntime = Fixture.tab(secondID, path: "/batch/runtime-second", pinned: true)
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [firstRuntime, secondRuntime],
            active: firstID,
        )
        source.contentTabs.pinnedRecords[firstID] = Fixture.pinRecord(for: firstProjection)
        source.contentTabs.pinnedRecords[secondID] = Fixture.pinRecord(for: secondProjection)
        var targetTabs = [firstProjection, secondProjection]
        targetTabs += (0 ..< ContentTabConstants.maxTabs - 2).map {
            Fixture.tab(ContentTabID(rawValue: "batch-capacity-filler-\($0)"), path: "/batch/filler/\($0)")
        }
        let targetActiveID = try XCTUnwrap(targetTabs.last?.id)
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: targetTabs,
            active: targetActiveID,
        )
        target.contentTabs.pinnedRecords[firstID] = Fixture.pinRecord(for: firstProjection)
        target.contentTabs.pinnedRecords[secondID] = Fixture.pinRecord(for: secondProjection)

        let postCommit = try batchPostCommit(
            source: source,
            target: target,
            orderedTabIDs: [secondID, firstID],
            primaryTabID: firstID,
            closesSource: true,
        )

        XCTAssertEqual(postCommit.target.contentTabs.tabs.count, ContentTabConstants.maxTabs)
        XCTAssertEqual(postCommit.target.contentTabs.tabs[id: firstID], firstRuntime)
        XCTAssertEqual(postCommit.target.contentTabs.tabs[id: secondID], secondRuntime)
        XCTAssertEqual(postCommit.target.contentTabs.tabs.count(where: { $0.id == firstID }), 1)
        XCTAssertEqual(postCommit.target.contentTabs.tabs.count(where: { $0.id == secondID }), 1)
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: 마지막 invalid member는 batch 전체를 reject한다.
    /// 앞선 valid work unit을 부분 적용하지 않고 collision과 work-unit 실패를 fail-closed로 처리한다.
    /// - 검증 내용: last member tab collision/malformed ownership rejection과 full snapshot equality
    /// - 사전 조건: ordered batch의 첫 member는 valid이고 마지막 member만 invalid하다.
    /// - 기대 결과: 두 경우 모두 source/target이 완전히 동일하고 success token이 생성되지 않는다.
    func testBatchRejectsLastMemberCollisionAndMalformedWorkUnitWithoutMutation() throws {
        let firstID = ContentTabID(rawValue: "batch-reject-first")
        let lastID = ContentTabID(rawValue: "batch-reject-last")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(firstID, path: "/batch/reject-first"),
                Fixture.tab(lastID, path: "/batch/reject-last"),
            ],
            active: firstID,
        )
        let collisionTarget = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(lastID, path: "/batch/divergent-last")],
            active: lastID,
        )
        try assertBatchRejected(
            .targetTabCollision,
            source: source,
            target: collisionTarget,
            orderedTabIDs: [firstID, lastID],
            primaryTabID: firstID,
        )

        var malformedSource = source
        malformedSource.tabContentStates[lastID] = nil
        let emptyTarget = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        try assertBatchRejected(
            .ineligible(.malformedOwnership),
            source: malformedSource,
            target: emptyTarget,
            orderedTabIDs: [firstID, lastID],
            primaryTabID: firstID,
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: batch ordered IDs와 primary를 엄격히 normalize한다.
    /// empty/duplicate/missing/member가 아닌 primary가 mutation 전에 reject되는지 검증한다.
    /// - 검증 내용: ordered IDs nonempty/unique/source membership와 primary membership
    /// - 사전 조건: valid source/target에 invalid batch 입력만 각각 주입한다.
    /// - 기대 결과: sourceTabMissing/sourceTabAmbiguous로 reject되고 양 snapshot은 불변이다.
    func testBatchRejectsInvalidOrderedIDsAndPrimaryWithoutMutation() throws {
        let firstID = ContentTabID(rawValue: "batch-normalize-first")
        let secondID = ContentTabID(rawValue: "batch-normalize-second")
        let missingID = ContentTabID(rawValue: "batch-normalize-missing")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(firstID, path: "/batch/normalize-first"),
                Fixture.tab(secondID, path: "/batch/normalize-second"),
            ],
            active: firstID,
        )
        let target = Fixture.window(windowID: Fixture.targetWindowID, tabs: [], active: nil)
        let cases: [BatchRejectionCase] = [
            .init(expected: .sourceTabMissing, orderedTabIDs: [], primaryTabID: firstID),
            .init(expected: .sourceTabAmbiguous, orderedTabIDs: [firstID, firstID], primaryTabID: firstID),
            .init(expected: .sourceTabMissing, orderedTabIDs: [firstID, missingID], primaryTabID: firstID),
            .init(expected: .sourceTabMissing, orderedTabIDs: [firstID], primaryTabID: secondID),
        ]

        for rejectionCase in cases {
            try assertBatchRejected(
                rejectionCase.expected,
                source: source,
                target: target,
                orderedTabIDs: rejectionCase.orderedTabIDs,
                primaryTabID: rejectionCase.primaryTabID,
            )
        }
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: single API는 batch-of-one과 동등하다.
    /// 기존 preflight/apply/transfer wrapper가 새 batch token과 결과를 그대로 재사용하는지 검증한다.
    /// - 검증 내용: singleton SuccessToken equality와 final Result equality
    /// - 사전 조건: 기존 complete single transfer scenario
    /// - 기대 결과: single과 batch preflight token 및 transfer outcome이 완전히 동일하다.
    func testSingletonPreflightAndTransferDelegateToBatchOfOne() throws {
        let scenario = CompleteTransferScenario()

        let singlePreflight = ContentTabTransfer.preflight(
            source: scenario.source,
            target: scenario.target,
            tabID: scenario.movedID,
        )
        let batchPreflight = ContentTabTransfer.preflight(
            source: scenario.source,
            target: scenario.target,
            orderedTabIDs: [scenario.movedID],
            primaryTabID: scenario.movedID,
        )
        let singleToken = try singlePreflight.successToken()
        let batchToken = try batchPreflight.successToken()

        XCTAssertEqual(singleToken, batchToken)
        XCTAssertEqual(ContentTabTransfer.apply(singleToken), ContentTabTransfer.apply(batchToken))
        XCTAssertEqual(
            ContentTabTransfer.transfer(
                source: scenario.source,
                target: scenario.target,
                tabID: scenario.movedID,
            ),
            ContentTabTransfer.transfer(
                source: scenario.source,
                target: scenario.target,
                orderedTabIDs: [scenario.movedID],
                primaryTabID: scenario.movedID,
            ),
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: target domain이 없으면 기존 preserve-domain batch transfer를
    /// 유지한다.
    /// Task 4 semantic helper가 명시 domain이 없는 foreign route를 기존 VOY-458 projection과 동일하게 위임하는지 검증한다.
    /// - 검증 내용: 기존 preflight/apply 결과와 semantic wrapper의 token/result equality
    /// - 사전 조건: mixed-domain frozen batch source와 기존 pinned/unpinned target
    /// - 기대 결과: targetDomain/placement가 nil이면 기존 batch projection과 완전히 동일하다.
    func testSemanticPreflightKeepsPreserveDomainTransferUnchangedWhenTargetDomainIsNil() throws {
        let scenario = MixedBatchTransferScenario()

        let baselineToken = try ContentTabTransfer.preflight(
            source: scenario.source,
            target: scenario.target,
            orderedTabIDs: scenario.orderedIDs,
            primaryTabID: scenario.unpinnedID,
        )
        .successToken()
        let semanticToken = try semanticPreflight(
            source: scenario.source,
            target: scenario.target,
            orderedTabIDs: scenario.orderedIDs,
            primaryTabID: scenario.unpinnedID,
            sourceDomain: nil,
            targetDomain: nil,
            placement: nil,
        ).successToken()

        XCTAssertEqual(semanticToken, baselineToken)
        XCTAssertNil(semanticToken.durablePinnedMutation)
        XCTAssertEqual(ContentTabTransfer.apply(semanticToken), ContentTabTransfer.apply(baselineToken))
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: explicit same-domain transfer는 requested placement를 그대로
    /// 따른다.
    /// foreign same-domain batch가 append fallback 없이 `.before`, `.after`, `.empty` 표면에 contiguous insertion 되는지 검증한다.
    /// - 검증 내용: same-domain target runtime ordering, moved-only selection, source survivor 보존
    /// - 사전 조건: unpinned before/after target과 pinned empty target에 같은 frozen batch를 사용한다.
    /// - 기대 결과: 각 placement가 target domain 내부 raw slot에 정확히 반영되고 source는 batch만 제거된다.
    func testSemanticPreflightSupportsExplicitSameDomainPlacement() throws {
        let firstID = ContentTabID(rawValue: "same-domain-first")
        let secondID = ContentTabID(rawValue: "same-domain-second")
        let survivorID = ContentTabID(rawValue: "same-domain-survivor")
        let pinnedTargetID = ContentTabID(rawValue: "same-domain-target-pinned")
        let unpinnedA = ContentTabID(rawValue: "same-domain-target-unpinned-a")
        let unpinnedB = ContentTabID(rawValue: "same-domain-target-unpinned-b")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(survivorID, path: "/same-domain/survivor"),
                Fixture.tab(firstID, path: "/same-domain/first"),
                Fixture.tab(secondID, path: "/same-domain/second"),
            ],
            active: survivorID,
        )
        let orderedIDs = [firstID, secondID]

        let beforeTarget = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(pinnedTargetID, path: "/same-domain/pinned", pinned: true),
                Fixture.tab(unpinnedA, path: "/same-domain/unpinned-a"),
                Fixture.tab(unpinnedB, path: "/same-domain/unpinned-b"),
            ],
            active: unpinnedA,
        )
        let beforeToken = try semanticPreflight(
            source: source,
            target: beforeTarget,
            orderedTabIDs: orderedIDs,
            primaryTabID: secondID,
            sourceDomain: .unpinned,
            targetDomain: .unpinned,
            placement: .before(unpinnedA),
        ).successToken()
        XCTAssertNil(beforeToken.durablePinnedMutation)
        let beforePostCommit = try ContentTabTransfer.apply(beforeToken).movedPostCommit()
        XCTAssertEqual(
            Array(beforePostCommit.target.contentTabs.tabs.ids),
            [pinnedTargetID, firstID, secondID, unpinnedA, unpinnedB],
        )
        XCTAssertEqual(beforePostCommit.target.contentTabs.selectedTabIDs, Set(orderedIDs))
        XCTAssertEqual(beforePostCommit.source.contentTabs.tabs.ids, [survivorID])

        let afterToken = try semanticPreflight(
            source: source,
            target: beforeTarget,
            orderedTabIDs: orderedIDs,
            primaryTabID: secondID,
            sourceDomain: .unpinned,
            targetDomain: .unpinned,
            placement: .after(unpinnedA),
        ).successToken()
        XCTAssertNil(afterToken.durablePinnedMutation)
        let afterPostCommit = try ContentTabTransfer.apply(afterToken).movedPostCommit()
        XCTAssertEqual(
            Array(afterPostCommit.target.contentTabs.tabs.ids),
            [pinnedTargetID, unpinnedA, firstID, secondID, unpinnedB],
        )

        let emptyPinnedTarget = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(unpinnedA, path: "/same-domain/empty-unpinned")],
            active: unpinnedA,
        )
        let pinnedSource = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(firstID, path: "/same-domain/pinned-first", pinned: true),
                Fixture.tab(secondID, path: "/same-domain/pinned-second", pinned: true),
            ],
            active: firstID,
        )
        .withPinnedRecords(for: [firstID, secondID])
        let emptyPinnedToken = try semanticPreflight(
            source: pinnedSource,
            target: emptyPinnedTarget,
            orderedTabIDs: orderedIDs,
            primaryTabID: firstID,
            sourceDomain: .pinned,
            targetDomain: .pinned,
            placement: .empty,
        ).successToken()
        XCTAssertEqual(
            emptyPinnedToken.durablePinnedMutation,
            .init(
                recordsToUpsert: [],
                recordIDsToRemove: [],
                orderedTabIDs: orderedIDs,
                pinnedPlacement: .empty,
            ),
        )
        let emptyPinnedPostCommit = try ContentTabTransfer.apply(emptyPinnedToken).closeSourceWindowPostCommit()
        XCTAssertEqual(
            Array(emptyPinnedPostCommit.target.contentTabs.tabs.ids),
            [firstID, secondID, unpinnedA],
        )
        XCTAssertEqual(
            emptyPinnedPostCommit.target.contentTabs.tabs.filter(\.isPinned).map(\.id),
            orderedIDs,
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: explicit opposite-domain transfer는 pinned
    /// marker/record와
    /// runtime placement를 함께 바꾼다.
    /// unpinned batch를 foreign pinned domain으로 옮길 때 requested placement 기준 contiguous block과 pinned record 생성이
    /// 함께 frozen 되는지 검증한다.
    /// - 검증 내용: opposite-domain pin target ordering, moved pinned markers/records, durable mutation timestamp equality
    /// - 사전 조건: unpinned source batch와 pinned/unpinned target을 before/empty placement로 각각 구성한다.
    /// - 기대 결과: moved batch는 pinned domain에 contiguous insertion 되고 새 pinned record는 주입된 timestamp를 그대로 쓴다.
    func testSemanticPreflightProjectsOppositeDomainPinPlacementAndPinnedRecords() throws {
        let firstID = ContentTabID(rawValue: "opposite-pin-first")
        let secondID = ContentTabID(rawValue: "opposite-pin-second")
        let targetPinnedA = ContentTabID(rawValue: "opposite-pin-target-a")
        let targetPinnedB = ContentTabID(rawValue: "opposite-pin-target-b")
        let targetUnpinned = ContentTabID(rawValue: "opposite-pin-target-unpinned")
        let projectedPinnedAt = Date(timeIntervalSince1970: 987)
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(firstID, path: "/opposite-pin/first"),
                Fixture.tab(secondID, path: "/opposite-pin/second"),
            ],
            active: secondID,
        )
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(targetPinnedA, path: "/opposite-pin/target-a", pinned: true),
                Fixture.tab(targetPinnedB, path: "/opposite-pin/target-b", pinned: true),
                Fixture.tab(targetUnpinned, path: "/opposite-pin/target-unpinned"),
            ],
            active: targetUnpinned,
        )
        target.contentTabs.pinnedRecords[targetPinnedA] = try Fixture
            .pinRecord(for: XCTUnwrap(target.contentTabs.tabs[id: targetPinnedA]))
        target.contentTabs.pinnedRecords[targetPinnedB] = try Fixture
            .pinRecord(for: XCTUnwrap(target.contentTabs.tabs[id: targetPinnedB]))

        let beforeToken = try semanticPreflight(
            source: source,
            target: target,
            orderedTabIDs: [firstID, secondID],
            primaryTabID: secondID,
            sourceDomain: .unpinned,
            targetDomain: .pinned,
            placement: .before(targetPinnedB),
            pinnedAt: projectedPinnedAt,
        ).successToken()
        XCTAssertEqual(
            Array(beforeToken.projectedTarget.contentTabs.tabs.ids),
            [targetPinnedA, firstID, secondID, targetPinnedB, targetUnpinned],
        )
        XCTAssertEqual(
            beforeToken.projectedTarget.contentTabs.tabs.filter(\.isPinned).map(\.id),
            [targetPinnedA, firstID, secondID, targetPinnedB],
        )
        XCTAssertNotNil(beforeToken.projectedTarget.contentTabs.pinnedRecords[firstID])
        XCTAssertNotNil(beforeToken.projectedTarget.contentTabs.pinnedRecords[secondID])
        XCTAssertEqual(
            beforeToken.durablePinnedMutation,
            .init(
                recordsToUpsert: [
                    Fixture.pinRecord(
                        for: Fixture.tab(firstID, path: "/opposite-pin/first", pinned: true),
                        pinnedAt: projectedPinnedAt,
                    ),
                    Fixture.pinRecord(
                        for: Fixture.tab(secondID, path: "/opposite-pin/second", pinned: true),
                        pinnedAt: projectedPinnedAt,
                    ),
                ],
                recordIDsToRemove: [],
                orderedTabIDs: [firstID, secondID],
                pinnedPlacement: .before(targetPinnedB),
            ),
        )
        XCTAssertEqual(beforeToken.projectedTarget.contentTabs.pinnedRecords[firstID]?.pinnedAt, projectedPinnedAt)
        XCTAssertEqual(beforeToken.projectedTarget.contentTabs.pinnedRecords[secondID]?.pinnedAt, projectedPinnedAt)

        let emptyTarget = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetUnpinned, path: "/opposite-pin/empty-unpinned")],
            active: targetUnpinned,
        )
        let emptyToken = try semanticPreflight(
            source: source,
            target: emptyTarget,
            orderedTabIDs: [firstID, secondID],
            primaryTabID: firstID,
            sourceDomain: .unpinned,
            targetDomain: .pinned,
            placement: .empty,
            pinnedAt: projectedPinnedAt,
        ).successToken()
        XCTAssertEqual(
            Array(emptyToken.projectedTarget.contentTabs.tabs.ids),
            [firstID, secondID, targetUnpinned],
        )
        XCTAssertEqual(
            emptyToken.durablePinnedMutation,
            .init(
                recordsToUpsert: [
                    Fixture.pinRecord(
                        for: Fixture.tab(firstID, path: "/opposite-pin/first", pinned: true),
                        pinnedAt: projectedPinnedAt,
                    ),
                    Fixture.pinRecord(
                        for: Fixture.tab(secondID, path: "/opposite-pin/second", pinned: true),
                        pinnedAt: projectedPinnedAt,
                    ),
                ],
                recordIDsToRemove: [],
                orderedTabIDs: [firstID, secondID],
                pinnedPlacement: .empty,
            ),
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: visible empty pinned drop은 durable global order에
    /// 연결된다.
    /// suppressed pinned projection이 있는 창의 empty drop이 전역 empty로 오인되지 않는지 검증한다.
    /// - 검증 내용: runtime empty insertion과 durable pinned neighbor placement 분리
    /// - 사전 조건: target pinned section은 비어 보이지만 confirmed global order에는 suppressed pinned tab이 있다.
    /// - 기대 결과: runtime은 empty slot에 삽입되고 durable mutation은 suppressed global tab 뒤에 연결된다.
    func testSemanticPreflightNormalizesVisibleEmptyPinnedDropToDurableGlobalNeighbor() throws {
        let movedID = ContentTabID(rawValue: "visible-empty-moved")
        let globalPinnedID = ContentTabID(rawValue: "visible-empty-global-pinned")
        let targetUnpinnedID = ContentTabID(rawValue: "visible-empty-target-unpinned")
        let pinnedAt = Date(timeIntervalSince1970: 1234)
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(movedID, path: "/visible-empty/moved")],
            active: movedID,
        )
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetUnpinnedID, path: "/visible-empty/target")],
            active: targetUnpinnedID,
        )
        target.suppressedPinnedTabIDs = [globalPinnedID]
        target.lastConfirmedTopNavigationOrder = .init(items: [.contentTab(globalPinnedID)])

        let token = try semanticPreflight(
            source: source,
            target: target,
            orderedTabIDs: [movedID],
            primaryTabID: movedID,
            sourceDomain: .unpinned,
            targetDomain: .pinned,
            placement: .empty,
            pinnedAt: pinnedAt,
        ).successToken()

        XCTAssertEqual(token.projectedTarget.contentTabs.tabs.ids, [movedID, targetUnpinnedID])
        XCTAssertEqual(token.durablePinnedMutation?.pinnedPlacement, .after(globalPinnedID))
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: opposite-domain Pin은 deterministic timestamp 없이는
    /// whole-request를 reject한다.
    /// pure projection이 production time fallback을 만들지 않도록 preflight 단계에서 명시 timestamp를 강제한다.
    /// - 검증 내용: typed rejection과 source/target snapshot immutability
    /// - 사전 조건: unpinned source batch를 pinned target domain으로 보내되 pinnedAt은 nil이다.
    /// - 기대 결과: success token 없이 reject되고 source/target은 변경되지 않는다.
    func testSemanticPreflightRejectsOppositeDomainPinWithoutPinnedTimestamp() throws {
        let firstID = ContentTabID(rawValue: "missing-pinned-at-first")
        let secondID = ContentTabID(rawValue: "missing-pinned-at-second")
        let targetPinned = ContentTabID(rawValue: "missing-pinned-at-target-pinned")
        let targetUnpinned = ContentTabID(rawValue: "missing-pinned-at-target-unpinned")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(firstID, path: "/missing-pinned-at/first"),
                Fixture.tab(secondID, path: "/missing-pinned-at/second"),
            ],
            active: firstID,
        )
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(targetPinned, path: "/missing-pinned-at/pinned", pinned: true),
                Fixture.tab(targetUnpinned, path: "/missing-pinned-at/unpinned"),
            ],
            active: targetUnpinned,
        )
        target.contentTabs.pinnedRecords[targetPinned] = try Fixture
            .pinRecord(for: XCTUnwrap(target.contentTabs.tabs[id: targetPinned]))

        try assertSemanticRejected(
            .missingPinnedTimestamp,
            source: source,
            target: target,
            request: SemanticTransferRequest(
                orderedTabIDs: [firstID, secondID],
                primaryTabID: firstID,
                sourceDomain: .unpinned,
                targetDomain: .pinned,
                placement: .before(targetPinned),
            ),
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: explicit opposite-domain Unpin은 runtime placement만 바꾸고
    /// durable pinned order에서는 제거한다.
    /// pinned batch를 foreign unpinned domain으로 옮길 때 target runtime은 requested slot에 contiguous insertion 되지만
    /// durable pinned projection은 moved IDs를 보존하지 않는지 검증한다.
    /// - 검증 내용: opposite-domain unpin runtime ordering, pinned record removal, durable pinned order removal
    /// - 사전 조건: pinned source batch와 pinned/unpinned target, explicit `.after` placement
    /// - 기대 결과: target runtime은 unpinned slot으로 재배치되고 durable projection에는 기존 target pinned만 남는다.
    func testSemanticPreflightProjectsOppositeDomainUnpinAsRuntimeOnlyPlacement() throws {
        let firstID = ContentTabID(rawValue: "opposite-unpin-first")
        let secondID = ContentTabID(rawValue: "opposite-unpin-second")
        let targetPinned = ContentTabID(rawValue: "opposite-unpin-target-pinned")
        let targetUnpinnedA = ContentTabID(rawValue: "opposite-unpin-target-a")
        let targetUnpinnedB = ContentTabID(rawValue: "opposite-unpin-target-b")
        let pinnedFirst = Fixture.tab(firstID, path: "/opposite-unpin/first", pinned: true)
        let pinnedSecond = Fixture.tab(secondID, path: "/opposite-unpin/second", pinned: true)
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [pinnedFirst, pinnedSecond],
            active: firstID,
        )
        source.contentTabs.pinnedRecords[firstID] = Fixture.pinRecord(for: pinnedFirst)
        source.contentTabs.pinnedRecords[secondID] = Fixture.pinRecord(for: pinnedSecond)
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(targetPinned, path: "/opposite-unpin/target-pinned", pinned: true),
                Fixture.tab(targetUnpinnedA, path: "/opposite-unpin/target-a"),
                Fixture.tab(targetUnpinnedB, path: "/opposite-unpin/target-b"),
            ],
            active: targetUnpinnedA,
        )
        target.contentTabs.pinnedRecords[targetPinned] = try Fixture
            .pinRecord(for: XCTUnwrap(target.contentTabs.tabs[id: targetPinned]))

        let token = try semanticPreflight(
            source: source,
            target: target,
            orderedTabIDs: [firstID, secondID],
            primaryTabID: secondID,
            sourceDomain: .pinned,
            targetDomain: .unpinned,
            placement: .after(targetUnpinnedA),
        ).successToken()

        XCTAssertEqual(
            Array(token.projectedTarget.contentTabs.tabs.ids),
            [targetPinned, targetUnpinnedA, firstID, secondID, targetUnpinnedB],
        )
        XCTAssertEqual(
            token.projectedTarget.contentTabs.tabs.filter { !$0.isPinned }.map(\.id),
            [targetUnpinnedA, firstID, secondID, targetUnpinnedB],
        )
        XCTAssertNil(token.projectedTarget.contentTabs.pinnedRecords[firstID])
        XCTAssertNil(token.projectedTarget.contentTabs.pinnedRecords[secondID])
        XCTAssertEqual(
            token.durablePinnedMutation,
            .init(
                recordsToUpsert: [],
                recordIDsToRemove: [firstID.rawValue, secondID.rawValue],
                orderedTabIDs: [firstID, secondID],
                pinnedPlacement: nil,
            ),
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: foreign explicit Unpin은 target의 동일 global pinned
    /// projection을 안전하게 교체한다.
    /// 첫 Pin 이동으로 모든 창에 materialize된 passive pinned replica가 역방향 이동을 막지 않는지 검증한다.
    /// - 검증 내용: 두 passive pinned replacement, requested unpinned placement, remove-only durable mutation
    /// - 사전 조건: source와 target에 같은 pinned batch가 있고 target replica는 passive projection이다.
    /// - 기대 결과: target replica가 중복 없이 unpinned batch로 교체되고 pinned records는 durable removal 대상이 된다.
    func testSemanticUnpinReplacesPassiveGlobalPinnedProjectionsInTargetWindow() throws {
        let firstID = ContentTabID(rawValue: "round-trip-unpin-first")
        let secondID = ContentTabID(rawValue: "round-trip-unpin-second")
        let targetUnpinnedA = ContentTabID(rawValue: "round-trip-unpin-target-a")
        let targetUnpinnedB = ContentTabID(rawValue: "round-trip-unpin-target-b")
        let firstPinned = Fixture.tab(firstID, path: "/round-trip-unpin/first", pinned: true)
        let secondPinned = Fixture.tab(secondID, path: "/round-trip-unpin/second", pinned: true)
        let firstRecord = Fixture.pinRecord(for: firstPinned)
        let secondRecord = Fixture.pinRecord(for: secondPinned)
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [firstPinned, secondPinned],
            active: firstID,
        )
        source.contentTabs.pinnedRecords = [firstID: firstRecord, secondID: secondRecord]
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                firstPinned,
                secondPinned,
                Fixture.tab(targetUnpinnedA, path: "/round-trip-unpin/target-a"),
                Fixture.tab(targetUnpinnedB, path: "/round-trip-unpin/target-b"),
            ],
            active: targetUnpinnedA,
        )
        target.contentTabs.pinnedRecords = [firstID: firstRecord, secondID: secondRecord]

        let token = try semanticPreflight(
            source: source,
            target: target,
            orderedTabIDs: [firstID, secondID],
            primaryTabID: firstID,
            sourceDomain: .pinned,
            targetDomain: .unpinned,
            placement: .after(targetUnpinnedA),
        ).successToken()

        XCTAssertEqual(
            Array(token.projectedTarget.contentTabs.tabs.ids),
            [targetUnpinnedA, firstID, secondID, targetUnpinnedB],
        )
        XCTAssertEqual(token.projectedTarget.contentTabs.tabs.filter(\.isPinned).map(\.id), [])
        XCTAssertNil(token.projectedTarget.contentTabs.pinnedRecords[firstID])
        XCTAssertNil(token.projectedTarget.contentTabs.pinnedRecords[secondID])
        XCTAssertEqual(
            token.durablePinnedMutation,
            .init(
                recordsToUpsert: [],
                recordIDsToRemove: [firstID.rawValue, secondID.rawValue],
                orderedTabIDs: [firstID, secondID],
                pinnedPlacement: nil,
            ),
        )
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: explicit pinned self-anchor는 passive projection 교체로
    /// 정규화한다.
    /// 다른 창의 동일 global pinned projection 위 drop이 stale self-anchor rejection 없이 원래 경계에 runtime owner를 복원하는지
    /// 검증한다.
    /// - 검증 내용: before/after self-anchor의 adjacent/empty normalization, 중복 없는 ordering, source runtime owner 보존
    /// - 사전 조건: source pinned runtime tab과 target의 동일 ID passive projection 단독/양쪽 pinned neighbor 구성
    /// - 기대 결과: self-anchor는 surviving neighbor 또는 empty 경계로 정규화되고 target projection이 source owner로 교체된다.
    func testSemanticPreflightReplacesPassivePinnedSelfAnchorAtNormalizedBoundary() throws {
        let leadingID = ContentTabID(rawValue: "self-anchor-leading")
        let movedID = ContentTabID(rawValue: "self-anchor-moved")
        let trailingID = ContentTabID(rawValue: "self-anchor-trailing")
        let movedTab = Fixture.tab(movedID, path: "/self-anchor/moved", pinned: true)
        let movedRecord = Fixture.pinRecord(for: movedTab)
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [movedTab],
            active: movedID,
        )
        source.contentTabs.pinnedRecords[movedID] = movedRecord
        source.content.pendingSelectEntryID = "/self-anchor/runtime-owner.txt"
        source.tabContentStates[movedID] = source.content

        try assertPassiveSelfAnchorWithNeighbors(
            source: source,
            movedTab: movedTab,
            movedRecord: movedRecord,
            leadingID: leadingID,
            trailingID: trailingID,
        )
        try assertLonePassiveSelfAnchor(
            source: source,
            movedTab: movedTab,
            movedRecord: movedRecord,
        )
    }

    private func assertPassiveSelfAnchorWithNeighbors(
        source: FileManagerWindowState,
        movedTab: ContentTabItem,
        movedRecord: ContentTabPinnedRecord,
        leadingID: ContentTabID,
        trailingID: ContentTabID,
    ) throws {
        let movedID = movedTab.id
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(leadingID, path: "/self-anchor/leading", pinned: true),
                movedTab,
                Fixture.tab(trailingID, path: "/self-anchor/trailing", pinned: true),
            ],
            active: leadingID,
        )
        target.contentTabs.pinnedRecords = try [
            leadingID: Fixture.pinRecord(for: XCTUnwrap(target.contentTabs.tabs[id: leadingID])),
            movedID: movedRecord,
            trailingID: Fixture.pinRecord(for: XCTUnwrap(target.contentTabs.tabs[id: trailingID])),
        ]

        for placement in [ContentTabPlacement.before(movedID), .after(movedID)] {
            let token = try semanticPreflight(
                source: source,
                target: target,
                orderedTabIDs: [movedID],
                primaryTabID: movedID,
                sourceDomain: .pinned,
                targetDomain: .pinned,
                placement: placement,
            ).successToken()

            XCTAssertEqual(token.durablePinnedMutation?.pinnedPlacement, .before(trailingID))
            XCTAssertEqual(Array(token.projectedTarget.contentTabs.tabs.ids), [leadingID, movedID, trailingID])
            XCTAssertEqual(token.projectedTarget.contentTabs.tabs.count(where: { $0.id == movedID }), 1)
            XCTAssertEqual(
                token.projectedTarget.tabContentStates[movedID]?.pendingSelectEntryID,
                "/self-anchor/runtime-owner.txt",
            )
            _ = try ContentTabTransfer.apply(token).closeSourceWindowPostCommit()
        }
    }

    private func assertLonePassiveSelfAnchor(
        source: FileManagerWindowState,
        movedTab: ContentTabItem,
        movedRecord: ContentTabPinnedRecord,
    ) throws {
        let movedID = movedTab.id
        var loneTarget = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [movedTab],
            active: movedID,
        )
        loneTarget.contentTabs.pinnedRecords[movedID] = movedRecord
        let loneToken = try semanticPreflight(
            source: source,
            target: loneTarget,
            orderedTabIDs: [movedID],
            primaryTabID: movedID,
            sourceDomain: .pinned,
            targetDomain: .pinned,
            placement: .before(movedID),
        ).successToken()

        XCTAssertEqual(loneToken.durablePinnedMutation?.pinnedPlacement, .empty)
        XCTAssertEqual(Array(loneToken.projectedTarget.contentTabs.tabs.ids), [movedID])
        XCTAssertEqual(
            loneToken.projectedTarget.tabContentStates[movedID]?.pendingSelectEntryID,
            "/self-anchor/runtime-owner.txt",
        )
        _ = try ContentTabTransfer.apply(loneToken).closeSourceWindowPostCommit()
    }

    /// CTM-001-move_content_tab_to_another_file_manager_window: explicit semantic preflight는 invalid target anchor와
    /// domain parity 위반을 fail-closed로 거절한다.
    /// missing/stale/self/wrong-domain anchor와 non-empty `.empty` target, source pin parity mismatch가 축소 없이 reject되는지
    /// 검증한다.
    /// - 검증 내용: typed rejection과 source/target full snapshot equality
    /// - 사전 조건: explicit same/opposite domain request에 invalid anchor/domain state만 각각 하나씩 주입한다.
    /// - 기대 결과: success token 없이 reject되고 어떤 projection mutation도 일어나지 않는다.
    func testSemanticPreflightRejectsInvalidTargetPlacementAndSourceDomainParityWithoutMutation() throws {
        let firstID = ContentTabID(rawValue: "semantic-reject-first")
        let secondID = ContentTabID(rawValue: "semantic-reject-second")
        let targetPinned = ContentTabID(rawValue: "semantic-reject-target-pinned")
        let targetUnpinned = ContentTabID(rawValue: "semantic-reject-target-unpinned")
        let missingAnchorID = ContentTabID(rawValue: "semantic-reject-missing")
        let source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(firstID, path: "/semantic-reject/first"),
                Fixture.tab(secondID, path: "/semantic-reject/second"),
            ],
            active: firstID,
        )
        let target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [
                Fixture.tab(targetPinned, path: "/semantic-reject/pinned", pinned: true),
                Fixture.tab(targetUnpinned, path: "/semantic-reject/unpinned"),
            ],
            active: targetUnpinned,
        )

        try assertSemanticRejected(
            .sourcePinParity,
            source: source,
            target: target,
            request: SemanticTransferRequest(
                orderedTabIDs: [firstID, secondID],
                primaryTabID: firstID,
                sourceDomain: .pinned,
                targetDomain: .pinned,
                placement: .before(targetPinned),
            ),
        )
        try assertSemanticRejected(
            semanticPlacementRejection,
            source: source,
            target: target,
            request: SemanticTransferRequest(
                orderedTabIDs: [firstID, secondID],
                primaryTabID: firstID,
                sourceDomain: .unpinned,
                targetDomain: .unpinned,
                placement: .before(missingAnchorID),
            ),
        )
        try assertSemanticRejected(
            semanticPlacementRejection,
            source: source,
            target: target,
            request: SemanticTransferRequest(
                orderedTabIDs: [firstID, secondID],
                primaryTabID: firstID,
                sourceDomain: .unpinned,
                targetDomain: .unpinned,
                placement: .before(firstID),
            ),
        )
        try assertSemanticRejected(
            semanticPlacementRejection,
            source: source,
            target: target,
            request: SemanticTransferRequest(
                orderedTabIDs: [firstID, secondID],
                primaryTabID: firstID,
                sourceDomain: .unpinned,
                targetDomain: .unpinned,
                placement: .before(targetPinned),
            ),
        )
        try assertSemanticRejected(
            semanticPlacementRejection,
            source: source,
            target: target,
            request: SemanticTransferRequest(
                orderedTabIDs: [firstID, secondID],
                primaryTabID: firstID,
                sourceDomain: .unpinned,
                targetDomain: .unpinned,
                placement: .empty,
            ),
        )
    }

    private func batchPostCommit(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        primaryTabID: ContentTabID,
        closesSource: Bool = false,
    ) throws -> ContentTabTransfer.PostCommit {
        let preflight = ContentTabTransfer.preflight(
            source: source,
            target: target,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
        )
        let result = try ContentTabTransfer.apply(preflight.successToken())
        return closesSource
            ? try result.closeSourceWindowPostCommit()
            : try result.movedPostCommit()
    }

    private func semanticPostCommit(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        primaryTabID: ContentTabID,
        sourceDomain: ContentTabDomain?,
        targetDomain: ContentTabDomain?,
        placement: ContentTabPlacement?,
        pinnedAt: Date? = nil,
        closesSource: Bool = false,
    ) throws -> ContentTabTransfer.PostCommit {
        let preflight = semanticPreflight(
            source: source,
            target: target,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
            sourceDomain: sourceDomain,
            targetDomain: targetDomain,
            placement: placement,
            pinnedAt: pinnedAt,
        )
        let result = try ContentTabTransfer.apply(preflight.successToken())
        return closesSource
            ? try result.closeSourceWindowPostCommit()
            : try result.movedPostCommit()
    }

    private func assertBatchRejected(
        _ expected: ContentTabTransfer.Rejection,
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        primaryTabID: ContentTabID,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) throws {
        let sourceBefore = source
        let targetBefore = target
        let result = ContentTabTransfer.preflight(
            source: source,
            target: target,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
        )
        XCTAssertEqual(result.rejection, expected, file: file, line: line)
        XCTAssertEqual(source, sourceBefore, file: file, line: line)
        XCTAssertEqual(target, targetBefore, file: file, line: line)
    }

    private func assertRejected(
        _ expected: ContentTabTransfer.Rejection,
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        tabID: ContentTabID,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) throws {
        let sourceBefore = source
        let targetBefore = target
        let result = ContentTabTransfer.preflight(source: source, target: target, tabID: tabID)
        XCTAssertEqual(result.rejection, expected, file: file, line: line)
        XCTAssertEqual(source, sourceBefore, file: file, line: line)
        XCTAssertEqual(target, targetBefore, file: file, line: line)
    }

    private func assertSemanticRejected(
        _ expected: ContentTabTransfer.Rejection,
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        request: SemanticTransferRequest,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) throws {
        let sourceBefore = source
        let targetBefore = target
        let result = semanticPreflight(
            source: source,
            target: target,
            orderedTabIDs: request.orderedTabIDs,
            primaryTabID: request.primaryTabID,
            sourceDomain: request.sourceDomain,
            targetDomain: request.targetDomain,
            placement: request.placement,
            pinnedAt: request.pinnedAt,
        )
        XCTAssertEqual(result.rejection, expected, file: file, line: line)
        XCTAssertEqual(source, sourceBefore, file: file, line: line)
        XCTAssertEqual(target, targetBefore, file: file, line: line)
    }
}

private struct SemanticTransferRequest {
    let orderedTabIDs: [ContentTabID]
    let primaryTabID: ContentTabID
    let sourceDomain: ContentTabDomain?
    let targetDomain: ContentTabDomain?
    let placement: ContentTabPlacement?
    let pinnedAt: Date? = nil
}

private struct MixedBatchTransferScenario {
    let survivorID = ContentTabID(rawValue: "batch-survivor")
    let pinnedFirstID = ContentTabID(rawValue: "batch-pinned-first")
    let pinnedSecondID = ContentTabID(rawValue: "batch-pinned-second")
    let unpinnedID = ContentTabID(rawValue: "batch-unpinned")
    let targetPinnedID = ContentTabID(rawValue: "batch-target-pinned")
    let targetUnpinnedID = ContentTabID(rawValue: "batch-target-unpinned")
    let source: FileManagerWindowState
    let target: FileManagerWindowState

    var orderedIDs: [ContentTabID] {
        [pinnedSecondID, pinnedFirstID, unpinnedID]
    }

    var expectedTargetIDs: [ContentTabID] {
        [targetPinnedID, pinnedSecondID, pinnedFirstID, targetUnpinnedID, unpinnedID]
    }

    init() {
        let unrelatedID = ContentTabID(rawValue: "batch-unrelated")
        let pinnedFirst = Fixture.tab(pinnedFirstID, path: "/batch/pinned-first", pinned: true)
        let pinnedSecond = Fixture.tab(pinnedSecondID, path: "/batch/pinned-second", pinned: true)
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [
                Fixture.tab(survivorID, path: "/batch/survivor"),
                pinnedFirst,
                Fixture.tab(unrelatedID, path: "/batch/unrelated"),
                pinnedSecond,
                Fixture.tab(unpinnedID, path: "/batch/unpinned"),
            ],
            active: survivorID,
        )
        source.contentTabs.pinnedRecords[pinnedFirstID] = Fixture.pinRecord(for: pinnedFirst)
        source.contentTabs.pinnedRecords[pinnedSecondID] = Fixture.pinRecord(for: pinnedSecond)
        source.contentTabs.selectedTabIDs = [pinnedFirstID, pinnedSecondID, unpinnedID]
        source.contentTabs.selectionAnchorID = pinnedFirstID
        source.tabContentStates[pinnedFirstID]?.pendingSelectEntryID = "pinned-first-owner"
        source.tabContentStates[pinnedSecondID]?.pendingSelectEntryID = "pinned-second-owner"
        source.tabContentStates[unpinnedID]?.pendingSelectEntryID = "unpinned-owner"
        self.source = source

        let targetPinned = Fixture.tab(targetPinnedID, path: "/batch/target-pinned", pinned: true)
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [targetPinned, Fixture.tab(targetUnpinnedID, path: "/batch/target-unpinned")],
            active: targetUnpinnedID,
        )
        target.contentTabs.pinnedRecords[targetPinnedID] = Fixture.pinRecord(for: targetPinned)
        target.contentTabs.selectedTabIDs = [targetPinnedID, targetUnpinnedID]
        target.contentTabs.selectionAnchorID = targetPinnedID
        self.target = target
    }
}

private struct BatchRejectionCase {
    let expected: ContentTabTransfer.Rejection
    let orderedTabIDs: [ContentTabID]
    let primaryTabID: ContentTabID
}

private struct CompleteTransferScenario {
    let movedID = ContentTabID(rawValue: "moved")
    let previousID = ContentTabID(rawValue: "previous")
    let targetID = ContentTabID(rawValue: "target")
    let sessionID = AiChatSessionID(rawValue: Fixture.sessionUUID)
    let unrelatedSessionID = AiChatSessionID(
        rawValue: UUID(uuid: (16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
    )
    let targetUnrelatedSessionID = AiChatSessionID(
        rawValue: UUID(uuid: (16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)),
    )
    let unrelatedPinGeneration: UInt64 = 7
    let movedTab: ContentTabItem
    let movedContent: FileManagerContentState
    let movedInspector: FileManagerInspectorFeature.State
    let pinRecord: ContentTabPinnedRecord
    let unrelatedBackground: FileManagerContentState
    let unrelatedInspectorBackground: FileManagerInspectorFeature.State
    let targetUnrelatedBackground: FileManagerContentState
    let targetUnrelatedInspectorBackground: FileManagerInspectorFeature.State
    let source: FileManagerWindowState
    let target: FileManagerWindowState

    init() {
        let rightID = ContentTabID(rawValue: "right")
        movedTab = Fixture.collectionTab(movedID, url: URL(fileURLWithPath: "/tmp/moved.voycoll"), pinned: true)
        var source = Fixture.window(
            windowID: Fixture.sourceWindowID,
            tabs: [Fixture.tab(previousID, path: "/previous"), movedTab, Fixture.tab(rightID, path: "/right")],
            active: movedID,
            previous: previousID,
        )
        let content = Fixture.movedContent(
            source.tabContentStates[movedID] ?? .init(),
            sessionID: sessionID,
        )
        movedContent = content
        let inspector = Fixture.movedInspector(
            source.tabInspectorStates[movedID] ?? .init(),
            sessionID: sessionID,
        )
        movedInspector = inspector
        pinRecord = Fixture.pinRecord(for: movedTab)
        unrelatedBackground = FileManagerContentState.initialContent(for: .homeDefault)
        unrelatedInspectorBackground = .init()
        targetUnrelatedBackground = FileManagerContentState.initialContent(for: .homeDefault)
        targetUnrelatedInspectorBackground = .init()
        source.content = content
        source.tabContentStates[movedID] = content
        source.inspector = movedInspector
        source.tabInspectorStates[movedID] = movedInspector
        source.contentTabs.pinnedRecords[movedID] = pinRecord
        source.backgroundAiChatStates[sessionID] = content
        source.backgroundInspectorAiChatStates[sessionID] = inspector
        source.backgroundAiChatStates[unrelatedSessionID] = unrelatedBackground
        source.backgroundInspectorAiChatStates[unrelatedSessionID] = unrelatedInspectorBackground
        self.source = source
        var target = Fixture.window(
            windowID: Fixture.targetWindowID,
            tabs: [Fixture.tab(targetID, path: "/target")],
            active: targetID,
        )
        target.backgroundAiChatStates[targetUnrelatedSessionID] = targetUnrelatedBackground
        target.backgroundInspectorAiChatStates[targetUnrelatedSessionID] = targetUnrelatedInspectorBackground
        self.target = target
    }

    func postCommit() throws -> ContentTabTransfer.PostCommit {
        let preflight = ContentTabTransfer.preflight(source: source, target: target, tabID: movedID)
        return try ContentTabTransfer.apply(preflight.successToken()).movedPostCommit()
    }
}

private enum Fixture {
    static let sourceWindowID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 17))
    static let targetWindowID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 18))
    static let sessionUUID = UUID(uuid: (32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    static func tab(_ id: ContentTabID, path: String, pinned: Bool = false) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .directory,
            anchor: .directory(path: path),
            isPinned: pinned,
            title: path,
            iconName: "folder",
        )
    }

    static func collectionTab(_ id: ContentTabID, url: URL, pinned: Bool) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .collection,
            anchor: .collectionFile(url: url),
            isPinned: pinned,
            title: url.deletingPathExtension().lastPathComponent,
            iconName: "rectangle.stack",
        )
    }

    static func aiTab(_ id: ContentTabID, sessionID: String) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .aiChat,
            anchor: .aiChat(sessionID: sessionID),
            isPinned: false,
            title: "AI Chat",
            iconName: "sparkles",
        )
    }

    static func movedContent(
        _ seed: FileManagerContentState,
        sessionID: AiChatSessionID,
    ) -> FileManagerContentState {
        var content = seed
        content.pendingSelectEntryID = "/moved/selected.txt"
        let baselineContext = CollectionContext(query: "baseline", scopes: ["/baseline"], conditions: [])
        let reopenContext = CollectionContext(query: "restore", scopes: ["/restore"], conditions: [])
        content.collection.collectionContext = CollectionContext(
            query: "dirty draft",
            scopes: ["/draft"],
            conditions: [],
        )
        content.collection.collectionSession = CollectionDocumentSessionState(
            phase: .opened(kind: .definition, base: .ready, inflight: .none),
            document: .init(url: URL(fileURLWithPath: "/tmp/moved.voycoll"), name: "moved"),
            metadata: .init(
                lastRefreshAt: Date(timeIntervalSince1970: 440),
                baseline: CollectionBaseline(context: baselineContext),
                reopenContext: reopenContext,
            ),
        )
        content.entryViewLayout.entryOperations.undoRecords = [entryActionRecord("undo", idByte: 1)]
        content.entryViewLayout.entryOperations.redoRecords = [entryActionRecord("redo", idByte: 2)]
        content.aiChat.sessionID = sessionID
        content.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "keep this message"),
            AiChatMessage(role: .assistant, content: "kept"),
        ]
        return content
    }

    static func movedInspector(
        _ seed: FileManagerInspectorFeature.State,
        sessionID: AiChatSessionID,
    ) -> FileManagerInspectorFeature.State {
        var inspector = seed
        inspector.aiChat.sessionID = sessionID
        inspector.aiChat.transcriptHistory = [AiChatMessage(role: .assistant, content: "inspector kept")]
        return inspector
    }

    static func entryActionRecord(_ name: String, idByte: UInt8) -> EntryActionRecord {
        EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/tmp/\(name)-old", afterPath: "/tmp/\(name)-new")],
            id: UUID(uuid: (48, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, idByte)),
            timestamp: Date(timeIntervalSince1970: TimeInterval(idByte)),
        )
    }

    static func pinRecord(
        for tab: ContentTabItem,
        pinnedAt: Date = Date(timeIntervalSince1970: 450),
    ) -> ContentTabPinnedRecord {
        ContentTabPinnedRecord(
            id: tab.id.rawValue,
            page: tab.page,
            anchor: tab.anchor,
            title: tab.title,
            iconName: tab.iconName,
            pinnedAt: pinnedAt,
        )
    }

    static func window(
        windowID: UUID,
        tabs: [ContentTabItem],
        active: ContentTabID?,
        previous: ContentTabID? = nil,
    ) -> FileManagerWindowState {
        var state = FileManagerWindowState()
        state.contentTabs = ContentTabState(
            tabs: IdentifiedArrayOf(uniqueElements: tabs),
            activeTabID: active,
            previousActiveTabID: previous,
            recentlyClosed: ClosedContentTabSnapshot(
                page: .directory,
                anchor: .directory(path: "/closed"),
                wasPinned: false,
                closedAt: Date(timeIntervalSince1970: 449),
                title: "closed",
                iconName: "folder",
            ),
        )
        state.tabContentStates = [:]
        state.tabInspectorStates = [:]
        for tab in tabs {
            var content = FileManagerContentState.initialContent(for: tab.anchor)
            content.applyWindowContext(windowID: windowID)
            content.entryViewLayout.entryOperations.loadingCancellationOwnerID = windowID
            state.tabContentStates[tab.id] = content
            switch tab.anchor {
            case .directory, .collectionFile, .virtualCollection:
                state.tabInspectorStates[tab.id] = FileManagerInspectorFeature.State().tabSnapshot()
            case .homeDefault, .aiChat:
                break
            }
        }
        if let active, let activeContent = state.tabContentStates[active] {
            state.content = activeContent
            state.inspector = state.tabInspectorStates[active] ?? .init()
        } else {
            state.content.applyWindowContext(windowID: windowID)
            state.content.entryViewLayout.entryOperations.loadingCancellationOwnerID = windowID
            state.inspector = .init()
        }
        state.recentlyClosedNavigationRoute = .folder("/closed-route")
        state.syncContentTabSidebarItems()
        return state
    }

    static func rewindow(_ state: FileManagerWindowState, id: UUID) -> FileManagerWindowState {
        var copy = state
        copy.content.applyWindowContext(windowID: id)
        copy.content.entryViewLayout.entryOperations.loadingCancellationOwnerID = id
        for tabID in copy.tabContentStates.keys {
            copy.tabContentStates[tabID]?.applyWindowContext(windowID: id)
            copy.tabContentStates[tabID]?.entryViewLayout.entryOperations.loadingCancellationOwnerID = id
        }
        return copy
    }
}

private extension ContentTabTransfer.Preflight {
    func successToken() throws -> ContentTabTransfer.SuccessToken {
        guard case let .success(token) = self else {
            throw TransferTestError.expectedSuccess(rejection)
        }
        return token
    }

    var rejection: ContentTabTransfer.Rejection? {
        guard case let .rejected(reason) = self else { return nil }
        return reason
    }
}

private extension CTM001MoveContentTabToAnotherWindowTests {
    var semanticPlacementRejection: ContentTabTransfer.Rejection {
        .targetPlacementInvalid
    }

    func semanticPreflight(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        primaryTabID: ContentTabID,
        sourceDomain: ContentTabDomain?,
        targetDomain: ContentTabDomain?,
        placement: ContentTabPlacement?,
        pinnedAt: Date? = nil,
    ) -> ContentTabTransfer.Preflight {
        ContentTabTransfer.preflight(
            source: source,
            target: target,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
            sourceDomain: sourceDomain,
            targetDomain: targetDomain,
            placement: placement,
            pinnedAt: pinnedAt,
        )
    }
}

private extension ContentTabTransfer.Result {
    func movedPostCommit() throws -> ContentTabTransfer.PostCommit {
        guard case let .moved(postCommit) = self else {
            throw TransferTestError.expectedMoved
        }
        return postCommit
    }

    func closeSourceWindowPostCommit() throws -> ContentTabTransfer.PostCommit {
        guard case let .closeSourceWindow(postCommit) = self else {
            throw TransferTestError.expectedCloseSourceWindow
        }
        return postCommit
    }
}

private extension FileManagerWindowState {
    func withPinnedRecords(for tabIDs: [ContentTabID]) -> FileManagerWindowState {
        var copy = self
        for tabID in tabIDs {
            guard let tab = copy.contentTabs.tabs[id: tabID] else { continue }
            copy.contentTabs.pinnedRecords[tabID] = Fixture.pinRecord(for: tab)
        }
        return copy
    }
}

private enum TransferTestError: Error {
    case expectedSuccess(ContentTabTransfer.Rejection?)
    case expectedMoved
    case expectedCloseSourceWindow
}
