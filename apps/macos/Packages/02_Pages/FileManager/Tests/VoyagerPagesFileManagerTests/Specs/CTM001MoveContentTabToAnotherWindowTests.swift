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
    /// pinned tab도 target 기존 순서를 바꾸지 않고 끝에 append되는지 검증한다.
    /// - 검증 내용: exact tab/pin/Content/Inspector/AI identity, target active/previous, destination context,
    /// recently-closed 불변
    /// - 사전 조건: settled AI transcript와 pinned record를 포함한 complete transfer scenario
    /// - 기대 결과: target owner 1, moved tab active, 기존 target active가 previous이며 양 window close history 불변
    func testApplyPreservesCompleteTargetIdentityAndCloseHistory() throws {
        let scenario = CompleteTransferScenario()
        let postCommit = try scenario.postCommit()

        XCTAssertEqual(postCommit.target.contentTabs.tabs.last, scenario.movedTab)
        XCTAssertEqual(postCommit.target.contentTabs.activeTabID, scenario.movedID)
        XCTAssertEqual(postCommit.target.contentTabs.previousActiveTabID, scenario.targetID)
        XCTAssertEqual(postCommit.target.contentTabs.pinnedRecords[scenario.movedID], scenario.pinRecord)
        var expectedContent = scenario.movedContent
        expectedContent.applyWindowContext(windowID: Fixture.targetWindowID)
        expectedContent.entryViewLayout.entryOperations.loadingCancellationOwnerID = Fixture.targetWindowID
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

    /// CTM-001-move_content_tab_to_another_file_manager_window: background AI owner와 close history가 보존된다.
    /// moved Content/Inspector background owner만 이동하고 unrelated 양쪽 owner는 그대로인지 검증한다.
    /// - 검증 내용: background owner source 0/target 1, unrelated owner equality, destination context, close history
    /// - 사전 조건: source와 target 모두 unrelated background Content/Inspector owner를 보유
    /// - 기대 결과: moved owner는 target에 정확히 한 개, unrelated owner와 recently-closed 값은 불변
    func testApplyMovesBackgroundOwnersExactlyOnceAndPreservesUnrelatedOwners() throws {
        let scenario = CompleteTransferScenario()
        let postCommit = try scenario.postCommit()
        var expectedContent = scenario.movedContent
        expectedContent.applyWindowContext(windowID: Fixture.targetWindowID)
        expectedContent.entryViewLayout.entryOperations.loadingCancellationOwnerID = Fixture.targetWindowID

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
        XCTAssertEqual(postCommit.target.content.composer.cancellationOwnerID, Fixture.targetWindowID)
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
    /// source 이동이 target의 session 검색 또는 model selector presentation을 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: Content session-list query와 Inspector model-selector presentation의 atomic rejection
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
        inspectorAiTarget.inspector.aiChat.isModelSelectorPresented = true
        inspectorAiTarget.tabInspectorStates[tabID] = inspectorAiTarget.inspector.tabSnapshot()
        try assertRejected(.targetTabCollision, source: source, target: inspectorAiTarget, tabID: tabID)
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

    static func pinRecord(for tab: ContentTabItem) -> ContentTabPinnedRecord {
        ContentTabPinnedRecord(
            id: tab.id.rawValue,
            page: tab.page,
            anchor: tab.anchor,
            title: tab.title,
            iconName: tab.iconName,
            pinnedAt: Date(timeIntervalSince1970: 450),
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

private enum TransferTestError: Error {
    case expectedSuccess(ContentTabTransfer.Rejection?)
    case expectedMoved
    case expectedCloseSourceWindow
}
