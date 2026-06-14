import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentComposerSeedingTests: XCTestCase {
    func testComposerOpenSkipsSeedingWhenNavigationIsComputer() async {
        var initialState = makeInitialState()
        initialState.navigation.navigationState = .computer
        initialState.composer.isPresented = false

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
            $0.registryClient = .live(snapshot: .load())
        }

        await store.send(FileManagerContentAction.composer(.view(.setPresented(true)))) {
            $0.composer.isPresented = true
        }
    }

    func testComposerOpenSeedsRecentsVirtualContextWhenPristine() async {
        var initialState = makeInitialState()
        initialState.navigation.navigationState = .recents
        initialState.composer.isPresented = false

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
            $0.registryClient = .live(snapshot: .load())
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.composer(.view(.setPresented(true)))) {
            $0.composer.isPresented = true
        }

        await store.receive(\.composer.internal.applyCollectionDraftRestore)

        XCTAssertEqual(store.state.composer.conditions.count, 2)
        XCTAssertEqual(store.state.composer.conditions.first?.propertyKey, "last_used_date")
        XCTAssertEqual(
            store.state.composer.conditions.first?.values,
            [AppliedFilterValueUtils.recentsSinceAnyOpenedLiteral],
        )
        XCTAssertEqual(store.state.composer.conditions.last?.propertyKey, "content_type_tree")
        XCTAssertEqual(store.state.composer.conditions.last?.operatorCode, "neq")
        XCTAssertEqual(store.state.composer.conditions.last?.values, ["public.folder"])
        XCTAssertTrue(store.state.composer.scopeEditor.selection.isRootOnly)
        XCTAssertEqual(store.state.navigation.navigationState, .recents)
    }

    func testComposerOpenReplacesStaleFolderSeedWithRecentsVirtualContext() async {
        var initialState = makeInitialState()
        initialState.navigation.navigationState = .recents
        initialState.composer.isPresented = false
        initialState.composer.scopeEditor.selection = .fromLegacyScopes(["/tmp/voyager"])

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
            $0.registryClient = .live(snapshot: .load())
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.composer(.view(.setPresented(true)))) {
            $0.composer.isPresented = true
        }

        await store.receive(\.composer.internal.applyCollectionDraftRestore)

        XCTAssertEqual(store.state.composer.conditions.map(\.propertyKey), ["last_used_date", "content_type_tree"])
        XCTAssertTrue(store.state.composer.scopeEditor.selection.isRootOnly)
        XCTAssertEqual(store.state.navigation.navigationState, .recents)
    }

    func testComposerOpenPreservesEditedDraftOnRecentsRoute() async {
        var initialState = makeInitialState()
        initialState.navigation.navigationState = .recents
        initialState.composer.isPresented = false
        initialState.composer.scopeEditor.selection = .fromLegacyScopes(["/tmp/voyager"])
        initialState.composer.text = "kind:image"

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
            $0.registryClient = .live(snapshot: .load())
        }

        await store.send(FileManagerContentAction.composer(.view(.setPresented(true)))) {
            $0.composer.isPresented = true
        }

        XCTAssertTrue(store.state.composer.conditions.isEmpty)
        XCTAssertEqual(store.state.composer.scopeEditor.selection.legacyScopePaths, ["/tmp/voyager"])
    }

    func testComposerOpenReplacesStaleRecentsVirtualContextWithFolderSeed() async {
        var initialState = makeInitialState()
        initialState.navigation.navigationState = .folder("/tmp/voyager")
        initialState.composer.isPresented = false
        initialState.composer.conditions = makeRecentsVirtualConditions()

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
            $0.registryClient = .live(snapshot: .load())
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.composer(.view(.setPresented(true)))) {
            $0.composer = .init()
            $0.composer.isPresented = true
        }

        await store.receive { action in
            guard case let .composer(.internal(.scopeEditorSeedCurrentPath(path))) = action else {
                return false
            }
            return path == "/tmp/voyager"
        }

        XCTAssertTrue(store.state.composer.conditions.isEmpty)
        XCTAssertEqual(store.state.composer.scopeEditor.selection.legacyScopePaths, ["/tmp/voyager"])
    }

    func testComposerOpenPreservesEditedVirtualDraftOnFolderRoute() async {
        var initialState = makeInitialState()
        initialState.navigation.navigationState = .folder("/tmp/voyager")
        initialState.composer.isPresented = false
        initialState.composer.conditions = makeRecentsVirtualConditions()
        initialState.composer.text = "kind:image"

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
            $0.registryClient = .live(snapshot: .load())
        }

        await store.send(FileManagerContentAction.composer(.view(.setPresented(true)))) {
            $0.composer.isPresented = true
        }

        XCTAssertEqual(store.state.composer.conditions.map(\.propertyKey), ["last_used_date", "content_type_tree"])
        XCTAssertEqual(store.state.composer.text, "kind:image")
        XCTAssertTrue(store.state.composer.scopeEditor.selection.isRootOnly)
    }

    func testComposerOpenSeedsTagsVirtualContextWhenPristine() async {
        var initialState = makeInitialState()
        initialState.navigation.navigationState = .tags("Work")
        initialState.composer.isPresented = false

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
            $0.registryClient = .live(snapshot: .load())
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.composer(.view(.setPresented(true)))) {
            $0.composer.isPresented = true
        }

        await store.receive(\.composer.internal.applyCollectionDraftRestore)

        XCTAssertEqual(store.state.composer.conditions.count, 1)
        XCTAssertEqual(store.state.composer.conditions.first?.propertyKey, "tag_names")
        XCTAssertEqual(store.state.composer.conditions.first?.values, ["Work"])
        XCTAssertTrue(store.state.composer.scopeEditor.selection.isRootOnly)
        XCTAssertEqual(store.state.navigation.navigationState, .tags("Work"))
    }

    func testComposerOpenSeedsCurrentPathThroughBridgeAction() async {
        var initialState = makeInitialState()
        initialState.composer.isPresented = false

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
            $0.registryClient = .live(snapshot: .load())
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.composer(.view(.setPresented(true))))

        await store.receive { action in
            guard case let .composer(.internal(.scopeEditorSeedCurrentPath(path))) = action else {
                return false
            }
            return path == "/tmp/voyager"
        }
    }

    private func makeInitialState() -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/tmp/voyager")
        return state
    }

    private func makeRecentsVirtualConditions() -> [Condition] {
        [
            Condition(
                propertyKey: "last_used_date",
                propertyLabel: "Last opened",
                propertyType: "date",
                operatorCode: "gt",
                operatorLabel: "After",
                operatorValueArity: 1,
                operatorValueUIKind: "singleDate",
                valueType: "date",
                values: [AppliedFilterValueUtils.recentsSinceAnyOpenedLiteral],
            ),
            Condition(
                propertyKey: "content_type_tree",
                propertyLabel: "Content type tree",
                propertyType: "string",
                operatorCode: "neq",
                operatorLabel: "Not equal",
                operatorValueArity: 1,
                operatorValueUIKind: "singleText",
                valueType: "string",
                values: ["public.folder"],
            ),
        ]
    }
}
