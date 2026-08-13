import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class FileManagerHostFixturePhaseNotificationTests: XCTestCase {
    func test_fixtureStateSeedsWindowContextIntoReducerState() {
        let windowID = UUID()
        let state = FileManagerHostFixture.makeState(preset: .default, windowID: windowID)

        XCTAssertEqual(
            state.content.entryOperations.windowID,
            windowID,
        )
        XCTAssertEqual(state.content.composer.cancellationOwnerID, windowID)
    }

    func testDefaultFixtureSeedsSpecialContentTabs() throws {
        let windowID = UUID()
        let state = FileManagerHostFixture.makeState(preset: .default, windowID: windowID)
        let tabsByTitle = Dictionary(
            uniqueKeysWithValues: state.contentTabs.tabs.compactMap { tab in
                tab.title.map { ($0, tab) }
            },
        )

        XCTAssertEqual(state.contentTabs.tabs.compactMap(\.title), [
            "Home",
            "Recents",
            "Computer",
            "Collection",
            "AI Chat",
        ])
        XCTAssertEqual(state.sidebar.contentTabSidebarItems.map(\.title), [
            "Home",
            "Recents",
            "Computer",
            "Collection",
            "AI Chat",
        ])

        let homeTab = try XCTUnwrap(tabsByTitle["Home"])
        let recentsTab = try XCTUnwrap(tabsByTitle["Recents"])
        let computerTab = try XCTUnwrap(tabsByTitle["Computer"])
        let collectionTab = try XCTUnwrap(tabsByTitle["Collection"])
        let aiChatTab = try XCTUnwrap(tabsByTitle["AI Chat"])

        XCTAssertEqual(state.contentTabs.activeTabID, homeTab.id)
        XCTAssertEqual(homeTab.anchor, .homeDefault)
        XCTAssertEqual(recentsTab.anchor, .virtualCollection(id: "Recents"))
        XCTAssertEqual(computerTab.anchor, .virtualCollection(id: "Computer"))
        XCTAssertEqual(collectionTab.anchor, .virtualCollection(id: "Design Assets"))
        XCTAssertEqual(aiChatTab.anchor, .aiChat(sessionID: "00000000-0000-0000-0000-000000000001"))
        XCTAssertEqual(state.tabContentStates[recentsTab.id]?.navigation.navigationState, .recents)
        XCTAssertEqual(state.tabContentStates[computerTab.id]?.navigation.navigationState, .computer)
        XCTAssertEqual(state.tabContentStates[collectionTab.id]?.navigation.navigationState, .tags("Design Assets"))
        XCTAssertEqual(
            state.tabContentStates[aiChatTab.id]?.navigation.navigationState,
            .aiChat("00000000-0000-0000-0000-000000000001"),
        )
        XCTAssertTrue(state.tabContentStates.values.allSatisfy { $0.entryOperations.windowID == windowID })
    }

    func testFocusedScenarioFixturesKeepSingleHomeTab() {
        for preset in FileManagerHostPreset.allCases where preset != .default {
            let state = FileManagerHostFixture.makeState(preset: preset, windowID: UUID())

            if preset == .delayedTabSwitch {
                XCTAssertEqual(state.contentTabs.tabs.compactMap(\.title), ["Home", "Delayed Tab"])
                XCTAssertEqual(state.contentTabs.activeTabID, state.contentTabs.tabs.first?.id)
            } else {
                XCTAssertEqual(state.contentTabs.tabs.compactMap(\.title), ["Home"])
                XCTAssertEqual(state.contentTabs.activeTabID, state.contentTabs.tabs.first?.id)
            }
        }
    }

    func test_phaseNotification_decodesOnlyTheMatchingWindowIdentity() {
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let firstNotification = Notification(
            name: FileManagerHostFixture.phaseDidChange,
            userInfo: [
                FileManagerHostFixture.phaseUserInfoKey: "firstBatch",
                FileManagerHostFixture.phaseWindowIDUserInfoKey: firstWindowID,
            ],
        )
        let secondNotification = Notification(
            name: FileManagerHostFixture.phaseDidChange,
            userInfo: [
                FileManagerHostFixture.phaseUserInfoKey: "firstBatch",
                FileManagerHostFixture.phaseWindowIDUserInfoKey: secondWindowID,
            ],
        )

        XCTAssertEqual(
            FileManagerHostFixture.phaseNotification(from: firstNotification),
            .init(phase: "firstBatch", windowID: firstWindowID),
        )
        XCTAssertNotEqual(
            FileManagerHostFixture.phaseNotification(from: secondNotification)?.windowID,
            firstWindowID,
        )
    }

    func test_phaseNotification_rejectsPayloadsWithoutWindowIdentity() {
        let notification = Notification(
            name: FileManagerHostFixture.phaseDidChange,
            userInfo: [FileManagerHostFixture.phaseUserInfoKey: "firstBatch"],
        )

        XCTAssertNil(FileManagerHostFixture.phaseNotification(from: notification))
    }

    func test_snapshotCaptureDirectory_isolatedByWindowIdentity() {
        let outputDirectory = URL(fileURLWithPath: "/tmp/FileManagerHostCapture", isDirectory: true)
        let firstWindowID = UUID()
        let secondWindowID = UUID()

        XCTAssertEqual(
            FileManagerHostFixture.snapshotCaptureDirectory(
                in: outputDirectory,
                windowID: firstWindowID,
            ),
            outputDirectory.appending(path: firstWindowID.uuidString, directoryHint: .isDirectory),
        )
        XCTAssertNotEqual(
            FileManagerHostFixture.snapshotCaptureDirectory(
                in: outputDirectory,
                windowID: firstWindowID,
            ),
            FileManagerHostFixture.snapshotCaptureDirectory(
                in: outputDirectory,
                windowID: secondWindowID,
            ),
        )
    }

    func test_progressiveFixtureSeedsNavigationAndHierarchyBeforeExpansionStreamStarts() async {
        let windowID = UUID()
        let state = FileManagerHostFixture.makeState(
            preset: .progressiveEntryLoading,
            windowID: windowID,
        )
        let projectsID = "/Fixture/FileManager/Projects"
        XCTAssertEqual(state.content.navigation.currentPath, "/Fixture/FileManager")
        XCTAssertEqual(state.content.entryViewLayout.hierarchy.rootPath, "/Fixture/FileManager")

        let store = TestStore(initialState: state.content.entryViewLayout) {
            EntryViewLayoutFeature()
        } withDependencies: {
            FileManagerHostFixture.applyDependencies(
                to: &$0,
                fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry(),
                progressiveEntryLoading: .success,
                windowID: windowID,
                workspaceClient: .previewValue,
            )
        }
        store.exhaustivity = .off // host launch 없이 expansion action과 fixture stream 진입만 검증한다.

        await store.send(.hierarchy(.folderExpansionRequested(id: projectsID))) {
            $0.hierarchy.setExpandedIDs([projectsID])
            $0.hierarchy.nodesByID[projectsID] = .init(
                expansionIntent: true,
                generation: 1,
                loadPhase: .loadingCore,
            )
        }
        await store.receive(\.delegate.expandRequested)
        await store.finish()
    }
}
