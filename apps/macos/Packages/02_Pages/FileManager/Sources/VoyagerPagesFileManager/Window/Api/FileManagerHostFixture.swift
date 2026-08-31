import AppKit
import ComposableArchitecture
import Foundation
import IdentifiedCollections
import UniformTypeIdentifiers
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

public struct FileManagerHostMaterialSurfaceConfiguration {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var alphaValue: CGFloat

    public init(
        material: NSVisualEffectView.Material,
        blendingMode: NSVisualEffectView.BlendingMode,
        alphaValue: CGFloat,
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.alphaValue = alphaValue
    }

    var materialOverride: FileManagerWindowMaterialOverride.Surface {
        FileManagerWindowMaterialOverride.Surface(
            material: material,
            blendingMode: blendingMode,
            alphaValue: alphaValue,
        )
    }
}

@MainActor
public struct FileManagerHostMaterialConfiguration {
    public typealias Surface = FileManagerHostMaterialSurfaceConfiguration

    public var windowShell: FileManagerHostMaterialSurfaceConfiguration
    public var contentBackground: FileManagerHostMaterialSurfaceConfiguration
    public var listHeader: FileManagerHostMaterialSurfaceConfiguration
    public var groupRowLightOpacity: CGFloat
    public var groupRowDarkOpacity: CGFloat

    public init(
        windowShell: FileManagerHostMaterialSurfaceConfiguration,
        contentBackground: FileManagerHostMaterialSurfaceConfiguration,
        listHeader: FileManagerHostMaterialSurfaceConfiguration = FileManagerHostMaterialSurfaceConfiguration(
            material: VoyagerDS.SurfaceMaterialRole.listHeaderSurface.material,
            blendingMode: VoyagerDS.SurfaceMaterialRole.listHeaderSurface.blendingMode,
            alphaValue: VoyagerDS.SurfaceMaterialRole.listHeaderSurface.alphaValue,
        ),
        groupRowLightOpacity: CGFloat = 0.035,
        groupRowDarkOpacity: CGFloat = 0.065,
    ) {
        self.windowShell = windowShell
        self.contentBackground = contentBackground
        self.listHeader = listHeader
        self.groupRowLightOpacity = groupRowLightOpacity
        self.groupRowDarkOpacity = groupRowDarkOpacity
    }

    public static var hostDefault: Self {
        Self(
            windowShell: FileManagerHostMaterialSurfaceConfiguration(
                material: VoyagerDS.SurfaceMaterialRole.windowShell.material,
                blendingMode: VoyagerDS.SurfaceMaterialRole.windowShell.blendingMode,
                alphaValue: VoyagerDS.SurfaceMaterialRole.windowShell.alphaValue,
            ),
            contentBackground: FileManagerHostMaterialSurfaceConfiguration(
                material: VoyagerDS.SurfaceMaterialRole.mainContentBackground.material,
                blendingMode: VoyagerDS.SurfaceMaterialRole.mainContentBackground.blendingMode,
                alphaValue: VoyagerDS.SurfaceMaterialRole.mainContentBackground.alphaValue,
            ),
        )
    }

    var materialOverride: FileManagerWindowMaterialOverride {
        FileManagerWindowMaterialOverride(
            windowShell: windowShell.materialOverride,
            contentBackground: contentBackground.materialOverride,
        )
    }
}

@MainActor
public enum FileManagerHostFixture {
    public typealias MaterialConfiguration = FileManagerHostMaterialConfiguration

    public struct PhaseNotification: Equatable, Sendable {
        public let phase: String
        public let windowID: UUID
        public let preset: String?
        public let requestID: UUID?
        public let errorCode: Int?
        public let rowCount: Int?

        public init(
            phase: String,
            windowID: UUID,
            preset: String? = nil,
            requestID: UUID? = nil,
            errorCode: Int? = nil,
            rowCount: Int? = nil,
        ) {
            self.phase = phase
            self.windowID = windowID
            self.preset = preset
            self.requestID = requestID
            self.errorCode = errorCode
            self.rowCount = rowCount
        }
    }

    nonisolated public static let phaseDidChange = Notification.Name("FileManagerHostFixture.phaseDidChange")
    nonisolated public static let phaseUserInfoKey = "phase"
    nonisolated public static let phaseWindowIDUserInfoKey = "windowID"
    nonisolated public static let phasePresetUserInfoKey = "preset"
    nonisolated public static let phaseRequestIDUserInfoKey = "requestID"
    nonisolated public static let phaseErrorCodeUserInfoKey = "errorCode"
    nonisolated public static let phaseRowCountUserInfoKey = "rowCount"

    nonisolated public static func snapshotCaptureDirectory(
        in outputDirectory: URL,
        windowID: UUID,
    ) -> URL {
        outputDirectory.appending(path: windowID.uuidString, directoryHint: .isDirectory)
    }

    nonisolated public static func phaseNotification(from notification: Notification) -> PhaseNotification? {
        guard notification.name == phaseDidChange,
              let phase = notification.userInfo?[phaseUserInfoKey] as? String,
              let windowID = notification.userInfo?[phaseWindowIDUserInfoKey] as? UUID
        else { return nil }

        return PhaseNotification(
            phase: phase,
            windowID: windowID,
            preset: notification.userInfo?[phasePresetUserInfoKey] as? String,
            requestID: notification.userInfo?[phaseRequestIDUserInfoKey] as? UUID,
            errorCode: notification.userInfo?[phaseErrorCodeUserInfoKey] as? Int,
            rowCount: notification.userInfo?[phaseRowCountUserInfoKey] as? Int,
        )
    }

    public static func makeWindowController(
        preset: FileManagerHostPreset = .default,
        oneDriveIcon: @escaping @Sendable () -> NSImage? = { nil },
        onBecameKey: (@MainActor (UUID) -> Void)? = nil,
        onWillClose: (@MainActor (UUID) -> Void)? = nil,
        materialConfiguration: MaterialConfiguration? = nil,
    ) -> FileManagerWindowCoordinator {
        @Dependency(\.uuid)
        var uuid
        let windowID = uuid()
        let fileOperationUndoManagerRegistry = FileOperationUndoManagerRegistry()
        let state = FileManagerHostFixtureStateFactory.makeState(preset: preset, windowID: windowID)
        let workspaceClient = WorkspaceClient.fileManagerHostFixture(oneDriveIcon: oneDriveIcon)
        let undoScopeResolver = FileManagerHostUndoScopeResolver()
        let store = Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            FileManagerHostFixtureDependencies.apply(
                to: &$0,
                context: .init(
                    scenario: preset.scenario,
                    preset: preset.rawValue,
                    windowID: windowID,
                    fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
                    workspaceClient: workspaceClient,
                    resolveUndoManagerScope: undoScopeResolver.resolve,
                ),
            )
        }
        undoScopeResolver.store = store

        return FileManagerWindowCoordinator(
            windowID: windowID,
            store: store,
            fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
            workspaceClient: workspaceClient,
            onBecameKey: onBecameKey,
            onWillClose: onWillClose,
            materialOverride: materialConfiguration?.materialOverride,
        )
    }

    public static func presentSwitcherIfNeeded(
        for preset: FileManagerHostPreset,
        in store: StoreOf<FileManagerFeature>,
    ) {
        guard let source = preset.switcherPresentationSource else { return }
        store.send(.request(.presentContentTabSwitcher(source: source)))
    }

    /// Host window가 mount된 뒤 fixture Projects folder의 deterministic stream을 시작한다.
    public static func startScenarioIfNeeded(
        for preset: FileManagerHostPreset,
        in windowController: FileManagerWindowCoordinator,
    ) {
        let scenario = preset.scenario
        guard scenario.progressiveEntryLoading != .none
            || scenario.delayedNavigation != .none
            || scenario.permission != .none
            || scenario.collection != .none
            || scenario.largeFolder != .none
        else { return }

        if scenario.collection == .directory {
            startCollectionScenarioIfNeeded(for: preset, windowID: windowController.windowID)
            return
        }

        runPostMountScenario(scenario: scenario, in: windowController)
    }

    public static func updateMaterialConfiguration(
        _ materialConfiguration: MaterialConfiguration?,
        in coordinator: FileManagerWindowCoordinator,
    ) {
        coordinator.updateMaterialOverride(materialConfiguration?.materialOverride)
        guard let contentView = coordinator.window?.contentView else { return }
        updateEntryListMaterialConfiguration(materialConfiguration, in: contentView)
    }

    static func startCollectionScenarioIfNeeded(
        for preset: FileManagerHostPreset,
        windowID: UUID,
    ) {
        guard preset.scenario.collection == .directory else { return }
        let rowCount = FileManagerHostFixtureSampleData.collectionEntries.count
        FileManagerHostFixturePhase.collectionStarted.log(
            preset: preset.rawValue,
            windowID: windowID,
            rowCount: rowCount,
        )
        FileManagerHostFixturePhase.collectionFinished.log(
            preset: preset.rawValue,
            windowID: windowID,
            rowCount: rowCount,
        )
    }

    static func makeEntryLoadingClient(
        preset: FileManagerHostPreset,
        windowID: UUID,
    ) -> EntryLoadingClient {
        .fileManagerHostFixture(
            scenario: preset.scenario,
            preset: preset.rawValue,
            windowID: windowID,
        )
    }

    static func makeState(
        preset: FileManagerHostPreset,
        windowID: UUID,
    ) -> FileManagerFeature.State {
        FileManagerHostFixtureStateFactory.makeState(
            preset: preset,
            windowID: windowID,
        )
    }

    static func applyDependencies(
        to dependencies: inout DependencyValues,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
        progressiveEntryLoading: FileManagerHostProgressiveEntryLoadingScenario,
        windowID: UUID,
        workspaceClient: WorkspaceClient,
    ) {
        FileManagerHostFixtureDependencies.apply(
            to: &dependencies,
            context: .init(
                scenario: FileManagerHostScenario(progressiveEntryLoading: progressiveEntryLoading),
                preset: nil,
                windowID: windowID,
                fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
                workspaceClient: workspaceClient,
                resolveUndoManagerScope: { _ in nil },
            ),
        )
    }

    private static func updateEntryListMaterialConfiguration(
        _ materialConfiguration: MaterialConfiguration?,
        in view: NSView,
    ) {
        if let entryListView = view as? EntryListView {
            let configuration = materialConfiguration ?? .hostDefault
            entryListView.updateMaterialAppearance(
                headerMaterial: configuration.listHeader.material,
                headerBlendingMode: configuration.listHeader.blendingMode,
                headerAlphaValue: configuration.listHeader.alphaValue,
                groupRowLightOpacity: configuration.groupRowLightOpacity,
                groupRowDarkOpacity: configuration.groupRowDarkOpacity,
            )
            return
        }
        for subview in view.subviews {
            updateEntryListMaterialConfiguration(materialConfiguration, in: subview)
        }
    }

    private static func runPostMountScenario(
        scenario: FileManagerHostScenario,
        in windowController: FileManagerWindowCoordinator,
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            switch scenario.delayedNavigation {
            case .rootNavigation:
                windowController.store.send(.navigation(.view(
                    .navigateToPath(FileManagerHostFixtureSampleData.delayedRootPath),
                )))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    windowController.store.send(.navigation(.view(
                        .navigateToPath(FileManagerHostFixtureSampleData.delayedRootReplacementPath),
                    )))
                }

            case .tabSwitch:
                windowController.store.send(.navigation(.view(
                    .navigateToPath(FileManagerHostFixtureSampleData.delayedTabPrimaryPath),
                )))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    windowController.store.send(.contentTabs(.setCurrent(
                        FileManagerHostFixtureStateFactory.delayedTabSwitchTargetID,
                    )))
                }

            case .none:
                let folderID: String = if scenario.permission != .none {
                    FileManagerHostFixtureSampleData.restrictedFolder.id
                } else if scenario.largeFolder != .none {
                    FileManagerHostFixtureSampleData.largeFolder.id
                } else {
                    FileManagerHostFixtureSampleData.projects.id
                }
                windowController.store.send(
                    .content(
                        .entryViewLayout(
                            .hierarchy(
                                .folderExpansionRequested(id: folderID),
                            ),
                        ),
                    ),
                )
                if scenario.permission == .retry {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                        windowController.store.send(.content(.entryViewLayout(.hierarchy(
                            .folderRetryRequested(id: folderID),
                        ))))
                    }
                }
            }
        }
    }
}

@MainActor
private final class FileManagerHostUndoScopeResolver {
    weak var store: StoreOf<FileManagerFeature>?

    func resolve(windowID: UUID) -> UndoManagerScope? {
        store?.withState { state in
            guard state.windowID == windowID,
                  let activeTabID = state.contentTabs.activeTabID
            else { return nil }
            return UndoManagerScope(windowID: windowID, contentTabID: activeTabID.rawValue)
        }
    }
}

@MainActor
private enum FileManagerHostFixtureStateFactory {
    fileprivate static let delayedTabSwitchTargetID = ContentTabID(rawValue: "file-manager-host-delayed-tab-target")
    private static let aiChatSessionID = "00000000-0000-0000-0000-000000000001"
    private static let homeTabID = ContentTabID(rawValue: "file-manager-host-home")
    private static let recentsTabID = ContentTabID(rawValue: "file-manager-host-recents")
    private static let computerTabID = ContentTabID(rawValue: "file-manager-host-computer")
    private static let collectionTabID = ContentTabID(rawValue: "file-manager-host-collection")
    private static let aiChatTabID = ContentTabID(rawValue: "file-manager-host-ai-chat")

    static func makeState(
        preset: FileManagerHostPreset,
        windowID: UUID,
    ) -> FileManagerFeature.State {
        let contentTabs: ContentTabState? = switch preset {
        case .contentTabSwitcherContent:
            FileManagerHostContentTabSwitcherContent.state
        case .contentTabSwitcherFallback:
            FileManagerHostContentTabSwitcherContent.fallbackState
        case .contentTabSwitcherEmpty:
            FileManagerHostContentTabSwitcherEmpty.state
        case .contentTabSwitcherLoading, .contentTabSwitcherError:
            FileManagerHostContentTabSwitcherContent.state
        default:
            nil
        }

        var state = FileManagerFeature.State.makeInitial(
            path: nil,
            contentTabs: contentTabs,
            windowID: windowID,
        )
        if preset == .contentTabSwitcherEmpty {
            state.contentTabs = .init()
        }
        if let contentTabs {
            state.contentTabs.recentlyUsedTabIDs = contentTabs.recentlyUsedTabIDs
            state.contentTabs.selectedTabIDs = FileManagerHostContentTabSwitcherContent.selectedTabIDs
            state.contentTabs.selectionAnchorID = FileManagerHostContentTabSwitcherContent.selectionAnchorID
        }
        state.sidebar.sidebarVisible = true
        state.sidebar.sidebarWidth = 220
        state.content.navigation.seedInitialFolderPath(FileManagerHostFixtureSampleData.path)
        state.content.applyWindowContext(windowID: windowID)
        state.content.entryViewLayout.mode = .list
        state.content.entryViewLayout.hierarchy.replaceRoot(path: FileManagerHostFixtureSampleData.path)
        state.content.entryViewLayout.entryOperations.items = IdentifiedArrayOf(
            uniqueElements: FileManagerHostFixtureSampleData.rootEntries(for: preset),
        )
        state.content.entryViewLayout.entries = Array(state.content.entryViewLayout.entryOperations.items)
        if preset == .default {
            seedSpecialContentTabs(in: &state)
        } else if preset == .delayedTabSwitch {
            seedDelayedTabSwitchTabs(in: &state)
        } else {
            state.syncActiveTabContentState()
        }
        for tabID in state.contentTabs.tabs.ids {
            state.tabContentStates[tabID]?.applyWindowContext(windowID: windowID)
        }
        if let activeTabID = state.contentTabs.activeTabID,
           let activeContent = state.tabContentStates[activeTabID]
        {
            state.content = activeContent
        }
        if preset == .collectionDirectory {
            applyCollectionDirectoryScenario(to: &state)
        }
        if preset.usesMaterialTuningFixture {
            applyMaterialTuningScenario(to: &state)
        }
        return state
    }

    private static func applyMaterialTuningScenario(to state: inout FileManagerFeature.State) {
        let entries = state.content.entryViewLayout.entries
        let groupNames = entries.reduce(into: [String]()) { names, entry in
            if !names.contains(entry.facets.kind) {
                names.append(entry.facets.kind)
            }
        }
        state.content.entryViewLayout.listVisibleColumns = EntryListColumn.allCases
        state.content.entryViewLayout.entryArrangements.groupKey = .kind
        state.content.entryViewLayout.entryArrangements.groupedItems = groupNames.map { groupName in
            .init(groupName: groupName, items: entries.filter { $0.facets.kind == groupName })
        }
        state.syncActiveTabContentState()
    }

    private static func applyCollectionDirectoryScenario(to state: inout FileManagerFeature.State) {
        state.content.navigation.navigationState = .collection(.init(
            kind: .temporary,
            context: .init(query: "Design Assets", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        state.content.collection.collectionContext = .init(
            query: "Design Assets",
            scopes: [],
            conditions: [],
        )
        state.content.entryViewLayout.isCollectionMode = true
        state.content.entryViewLayout.collectionItems = IdentifiedArrayOf(
            uniqueElements: FileManagerHostFixtureSampleData.collectionEntries,
        )
        state.content.entryViewLayout.hierarchy = .init()
        state.syncActiveTabContentState()
    }

    private static func seedDelayedTabSwitchTabs(in state: inout FileManagerFeature.State) {
        let home = state.contentTabs.tabs.first ?? makeTab(
            homeTabID,
            .home,
            .homeDefault,
            "Home",
            "house",
        )
        let target = makeTab(
            delayedTabSwitchTargetID,
            .directory,
            .directory(path: FileManagerHostFixtureSampleData.delayedTabSecondaryPath),
            "Delayed Tab",
            "folder",
        )
        state.contentTabs = ContentTabState(tabs: [home, target], activeTabID: home.id)
        state.tabContentStates = [
            home.id: state.content,
            target.id: FileManagerContentFeature.State.initialContent(
                for: target.anchor,
                inheritingWindowContextFrom: state.content,
            ),
        ]
        state.syncContentTabSidebarItems()
    }

    private static func seedSpecialContentTabs(in state: inout FileManagerFeature.State) {
        state.contentTabs = makeSpecialContentTabs()
        state.tabContentStates = makeSpecialContentStates(source: state.content)
        state.syncContentTabSidebarItems()
    }

    private static func makeSpecialContentTabs() -> ContentTabState {
        ContentTabState(
            tabs: [
                makeTab(homeTabID, .home, .homeDefault, "Home", "house"),
                makeTab(recentsTabID, .collection, .virtualCollection(id: "Recents"), "Recents", "clock"),
                makeTab(
                    computerTabID,
                    .collection,
                    .virtualCollection(id: "Computer"),
                    "Computer",
                    "desktopcomputer",
                ),
                makeTab(
                    collectionTabID,
                    .collection,
                    .virtualCollection(id: "Design Assets"),
                    "Collection",
                    "list.bullet",
                ),
                makeTab(aiChatTabID, .aiChat, .aiChat(sessionID: aiChatSessionID), "AI Chat", "message"),
            ],
            activeTabID: homeTabID,
        )
    }

    private static func makeTab(
        _ id: ContentTabID,
        _ page: ContentTabPage,
        _ anchor: ContentTabPageAnchor,
        _ title: String,
        _ iconName: String,
    ) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: page,
            anchor: anchor,
            isPinned: false,
            title: title,
            iconName: iconName,
        )
    }

    private static func makeSpecialContentStates(
        source: FileManagerContentFeature.State,
    ) -> [ContentTabID: FileManagerContentFeature.State] {
        var recentsContent = FileManagerContentFeature.State.initialContent(
            for: .virtualCollection(id: "Recents"),
            inheritingWindowContextFrom: source,
        )
        recentsContent.navigation.navigationState = .recents
        var computerContent = FileManagerContentFeature.State.initialContent(
            for: .virtualCollection(id: "Computer"),
            inheritingWindowContextFrom: source,
        )
        computerContent.navigation.navigationState = .computer
        let collectionContent = FileManagerContentFeature.State.initialContent(
            for: .virtualCollection(id: "Design Assets"),
            inheritingWindowContextFrom: source,
        )
        let aiChatContent = FileManagerContentFeature.State.initialContent(
            for: .aiChat(sessionID: aiChatSessionID),
            inheritingWindowContextFrom: source,
        )

        return [
            homeTabID: source,
            recentsTabID: recentsContent,
            computerTabID: computerContent,
            collectionTabID: collectionContent,
            aiChatTabID: aiChatContent,
        ]
    }
}

private enum FileManagerHostContentTabSwitcherContent {
    static let homeID = ContentTabID(rawValue: "content-home")
    static let activeDirectoryID = ContentTabID(rawValue: "content-active-directory")
    static let collectionID = ContentTabID(rawValue: "content-collection")
    static let virtualCollectionID = ContentTabID(rawValue: "content-virtual-collection")
    static let chatID = ContentTabID(rawValue: "content-ai-chat")
    static let cjkDirectoryID = ContentTabID(rawValue: "content-cjk-directory")
    static let longCollectionID = ContentTabID(rawValue: "content-long-collection")
    static let downloadsID = ContentTabID(rawValue: "content-downloads")
    static let pinnedFolderID = ContentTabID(rawValue: "content-pinned-folder")
    static let notesCollectionID = ContentTabID(rawValue: "content-notes-collection")

    static let state = ContentTabState(
        tabs: [
            ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            ),
            ContentTabItem(
                id: activeDirectoryID,
                page: .directory,
                anchor: .directory(path: "/Fixture/Projects/Voyager"),
                isPinned: false,
                title: "Voyager Projects",
                iconName: "folder",
            ),
            ContentTabItem(
                id: collectionID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/Fixture/Collections/Research.voycoll")),
                isPinned: false,
                title: "Research",
                iconName: "tray.full",
            ),
            ContentTabItem(
                id: virtualCollectionID,
                page: .collection,
                anchor: .virtualCollection(id: "fixture-virtual-collection"),
                isPinned: false,
                title: "Recent Documents",
                iconName: "clock",
            ),
            ContentTabItem(
                id: chatID,
                page: .aiChat,
                anchor: .aiChat(sessionID: "00000000-0000-0000-0000-000000000007"),
                isPinned: false,
                title: "Voyager Assistant",
                iconName: "sparkles",
            ),
            ContentTabItem(
                id: cjkDirectoryID,
                page: .directory,
                anchor: .directory(path: "/Fixture/문서/프로젝트"),
                isPinned: false,
                title: "프로젝트 문서",
                iconName: "folder",
            ),
            ContentTabItem(
                id: longCollectionID,
                page: .collection,
                anchor: .collectionFile(
                    url: URL(
                        fileURLWithPath:
                        "/Fixture/Collections/Very-Long-Research-Notes-For-The-Content-Tab-Switcher.voycoll",
                    ),
                ),
                isPinned: false,
                title: "A long collection title for switcher overflow",
                iconName: "rectangle.stack",
            ),
            ContentTabItem(
                id: downloadsID,
                page: .directory,
                anchor: .directory(path: "/Fixture/Downloads"),
                isPinned: false,
                title: "Downloads",
                iconName: "arrow.down.circle",
            ),
            ContentTabItem(
                id: pinnedFolderID,
                page: .directory,
                anchor: .directory(path: "/Fixture/Favorites"),
                isPinned: true,
                title: "Favorites",
                iconName: "star",
            ),
            ContentTabItem(
                id: notesCollectionID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/Fixture/Collections/Notes.voycoll")),
                isPinned: false,
                title: "Notes",
                iconName: "note.text",
            ),
        ],
        activeTabID: activeDirectoryID,
        recentlyUsedTabIDs: [
            chatID,
            longCollectionID,
            homeID,
            collectionID,
            activeDirectoryID,
            cjkDirectoryID,
            virtualCollectionID,
            downloadsID,
            pinnedFolderID,
            notesCollectionID,
        ],
    )

    static let fallbackState: ContentTabState = {
        var fallback = state
        fallback.tabs = IdentifiedArrayOf(uniqueElements: fallback.tabs.map { item in
            var item = item
            item.title = nil
            item.iconName = nil
            return item
        })
        return fallback
    }()

    static let selectedTabIDs: Set<ContentTabID> = [chatID, longCollectionID]
    static let selectionAnchorID: ContentTabID? = chatID
}

private enum FileManagerHostContentTabSwitcherEmpty {
    static let state = ContentTabState(
        tabs: [],
        activeTabID: nil,
        recentlyUsedTabIDs: [],
    )
}

@MainActor
enum FileManagerHostFixtureDependencies {
    struct ApplyContext {
        var scenario: FileManagerHostScenario
        var preset: String?
        var windowID: UUID
        var fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry
        var workspaceClient: WorkspaceClient
        var resolveUndoManagerScope: @MainActor @Sendable (UUID) -> UndoManagerScope?
    }

    static func apply(
        to dependencies: inout DependencyValues,
        context: ApplyContext,
    ) {
        dependencies.userDefaultsClient = .previewValue
        dependencies.metricsClient = .previewValue
        dependencies.fileManagerWindowClient = .previewValue
        dependencies.fileManagerIconClient = .previewValue
        dependencies.entryLoadingClient = .fileManagerHostFixture(
            scenario: context.scenario,
            preset: context.preset,
            windowID: context.windowID,
        )
        dependencies.fileManagerClient = .previewValue
        dependencies.fileManagerLocationsClient = .fileManagerHostFixture
        dependencies.notificationCenterClient = .previewValue
        dependencies.workspaceClient = context.workspaceClient
        dependencies.entryOpenClient = .previewValue
        dependencies.entryQuickLookClient = .previewValue
        dependencies.entryFileOpsClient = .previewValue
        dependencies.entryOperationsAlertClient = .previewValue
        dependencies.fileOperationUndoManagerClient = .live(registry: context.fileOperationUndoManagerRegistry)
        dependencies.undoManagerClient = .live(
            registry: context.fileOperationUndoManagerRegistry,
            resolveScope: context.resolveUndoManagerScope,
        )
        dependencies.registryClient = .testValue
        dependencies.collectionFileClient = .testValue
        dependencies.collectionAlertClient = .previewValue
        dependencies.collectionSavePanelClient = .previewValue
        dependencies.searchClient = .testValue
        dependencies.composerMetricClient = .testValue
    }
}

private extension FileManagerLocationsClient {
    static let fileManagerHostFixture = FileManagerLocationsClient { _ in
        [
            SidebarItems.LocationItem(
                name: "iCloud Drive",
                url: URL(fileURLWithPath: "/Fixture/Library/Mobile Documents/com~apple~CloudDocs"),
                iconName: "icloud",
            ),
            SidebarItems.LocationItem(
                name: "OneDrive",
                url: URL(fileURLWithPath: "/Fixture/Library/CloudStorage/OneDrive"),
                iconName: "folder",
            ),
            SidebarItems.LocationItem(
                name: "Fixture",
                url: URL(fileURLWithPath: "/Fixture"),
                iconName: "house",
            ),
            SidebarItems.LocationItem(
                name: "Macintosh HD",
                url: URL(fileURLWithPath: "/"),
                iconName: "internaldrive",
            ),
            SidebarItems.LocationItem(
                name: "Voyager External",
                url: URL(fileURLWithPath: "/Volumes/Voyager External"),
                iconName: "externaldrive",
            ),
            SidebarItems.LocationItem(
                name: "Trash",
                url: URL(fileURLWithPath: "/Fixture/.Trash"),
                iconName: "trash",
            ),
        ]
    }
}

private extension WorkspaceClient {
    static func fileManagerHostFixture(
        oneDriveIcon: @escaping @Sendable () -> NSImage?,
    ) -> WorkspaceClient {
        var client = WorkspaceClient.previewValue
        let previewIconForFile = client.iconForFile
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let homeDirectoryPath = homeDirectory.path
        let iCloudIconPath = "/System/Library/PrivateFrameworks/iCloudDriveCore.framework/Versions/A/Resources/"
            + "iCloudDrive.icns"
        nonisolated(unsafe) let workspace = NSWorkspace.shared
        let cachedIcons = FileManagerHostFixtureIconCache([
            "/Fixture/Library/Mobile Documents/com~apple~CloudDocs":
                Self.nonEmptyImage(NSImage(contentsOfFile: iCloudIconPath))
                ?? workspace.icon(for: .folder),
            "/Fixture/Library/CloudStorage/OneDrive":
                Self.nonEmptyImage(oneDriveIcon())
                ?? workspace.icon(for: .folder),
            "/Fixture": workspace.icon(forFile: homeDirectoryPath),
            "/": workspace.icon(forFile: "/"),
            "/Volumes/Voyager External": workspace.icon(for: .volume),
            "/Fixture/.Trash":
                Self.nonEmptyImage(NSImage(named: NSImage.trashEmptyName))
                ?? previewIconForFile("/Fixture/.Trash"),
        ])
        client.iconForFile = { path in
            cachedIcons.images[path] ?? previewIconForFile(path)
        }
        return client
    }

    private static func nonEmptyImage(_ image: NSImage?) -> NSImage? {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        return image
    }
}

private struct FileManagerHostFixtureIconCache: @unchecked Sendable {
    /// 이미지는 공개 전에 완성·변경하며, 이후 읽기 전용으로 사용한다.
    let images: [String: NSImage]

    init(_ images: [String: NSImage]) {
        self.images = images.mapValues { image in
            image.isTemplate = false
            return image
        }
    }
}
