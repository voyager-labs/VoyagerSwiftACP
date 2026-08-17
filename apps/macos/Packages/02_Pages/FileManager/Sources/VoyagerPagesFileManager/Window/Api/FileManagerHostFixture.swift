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

@MainActor
public enum FileManagerHostFixture {
    public struct MaterialConfiguration {
        public struct Surface {
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

        public var windowShell: Surface
        public var contentBackground: Surface

        public init(windowShell: Surface, contentBackground: Surface) {
            self.windowShell = windowShell
            self.contentBackground = contentBackground
        }

        public static var hostDefault: Self {
            Self(
                windowShell: Surface(
                    material: VoyagerDS.SurfaceMaterialRole.windowShell.material,
                    blendingMode: VoyagerDS.SurfaceMaterialRole.windowShell.blendingMode,
                    alphaValue: VoyagerDS.SurfaceMaterialRole.windowShell.alphaValue,
                ),
                contentBackground: Surface(
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
        let state = FileManagerHostFixtureStateFactory.makeState(windowID: windowID, preset: preset)
        let fileOperationUndoManagerRegistry = FileOperationUndoManagerRegistry()
        let fileOperationUndoManagerClient = FileOperationUndoManagerClient.live(
            registry: fileOperationUndoManagerRegistry,
        )
        let workspaceClient = WorkspaceClient.fileManagerHostFixture(oneDriveIcon: oneDriveIcon)
        let store = Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            FileManagerHostFixtureDependencies.apply(
                to: &$0,
                fileOperationUndoManagerClient: fileOperationUndoManagerClient,
                workspaceClient: workspaceClient,
            )
        }

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

    public static func updateMaterialConfiguration(
        _ materialConfiguration: MaterialConfiguration?,
        in coordinator: FileManagerWindowCoordinator,
    ) {
        coordinator.updateMaterialOverride(materialConfiguration?.materialOverride)
    }
}

@MainActor
private enum FileManagerHostFixtureStateFactory {
    static func makeState(windowID: UUID, preset: FileManagerHostPreset) -> FileManagerFeature.State {
        let contentTabs: ContentTabState? = switch preset {
        case .default:
            nil
        case .contentTabSwitcherContent:
            FileManagerHostContentTabSwitcherContent.state
        case .contentTabSwitcherFallback:
            FileManagerHostContentTabSwitcherContent.fallbackState
        case .contentTabSwitcherEmpty:
            FileManagerHostContentTabSwitcherEmpty.state
        case .contentTabSwitcherLoading, .contentTabSwitcherError:
            FileManagerHostContentTabSwitcherContent.state
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
        for tabID in state.contentTabs.tabs.ids {
            state.tabContentStates[tabID]?.entryViewLayout.entryOperations.windowID = windowID
        }
        if let activeTabID = state.contentTabs.activeTabID,
           let activeContent = state.tabContentStates[activeTabID]
        {
            state.content = activeContent
        }
        state.sidebar.sidebarVisible = true
        state.sidebar.sidebarWidth = 220
        state.content.entryViewLayout.currentPath = FileManagerHostFixtureSampleData.path
        state.content.entryViewLayout.mode = .list
        state.content.entryViewLayout.entryOperations.items = IdentifiedArrayOf(
            uniqueElements: FileManagerHostFixtureSampleData.entries,
        )
        state.content.entryViewLayout.entries = FileManagerHostFixtureSampleData.entries
        return state
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
private enum FileManagerHostFixtureDependencies {
    static func apply(
        to dependencies: inout DependencyValues,
        fileOperationUndoManagerClient: FileOperationUndoManagerClient,
        workspaceClient: WorkspaceClient,
    ) {
        dependencies.userDefaultsClient = .previewValue
        dependencies.metricsClient = .previewValue
        dependencies.fileManagerWindowClient = .previewValue
        dependencies.fileManagerIconClient = .previewValue
        dependencies.entryLoadingClient = .fileManagerHostFixture
        dependencies.fileManagerClient = .previewValue
        dependencies.fileManagerLocationsClient = .fileManagerHostFixture
        dependencies.notificationCenterClient = .previewValue
        dependencies.workspaceClient = workspaceClient
        dependencies.entryOpenClient = .previewValue
        dependencies.entryQuickLookClient = .previewValue
        dependencies.entryFileOpsClient = .previewValue
        dependencies.entryOperationsAlertClient = .previewValue
        dependencies.fileOperationUndoManagerClient = fileOperationUndoManagerClient
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
        let iCloudIconPath = "/System/Library/PrivateFrameworks/iCloudDriveCore.framework/Versions/A/Resources/iCloudDrive.icns"
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

private extension EntryLoadingClient {
    static let fileManagerHostFixture = EntryLoadingClient(
        loadItems: { _, _ in FileManagerHostFixtureSampleData.entries },
        loadComputerItems: { FileManagerHostFixtureSampleData.entries },
        loadRecentItems: { _, _ in FileManagerHostFixtureSampleData.entries },
        loadFilesWithTag: { _, _, _ in FileManagerHostFixtureSampleData.entries },
        fileExists: { _ in false },
        fileExistsAtPath: { _, _ in false },
        contentsOfDirectory: { _, _, _ in [] },
        mountedVolumeURLs: { _, _ in nil },
        urlsForDirectory: { directory, _ in
            switch directory {
            case .desktopDirectory:
                [URL(fileURLWithPath: "/Fixture/Desktop")]
            case .documentDirectory:
                [URL(fileURLWithPath: "/Fixture/Documents")]
            case .downloadsDirectory:
                [URL(fileURLWithPath: "/Fixture/Downloads")]
            case .applicationDirectory:
                [URL(fileURLWithPath: "/Fixture/Applications")]
            case .trashDirectory:
                [URL(fileURLWithPath: "/Fixture/.Trash")]
            default:
                []
            }
        },
        homeDirectory: { "/Fixture" },
        getItemMetadata: { _, _, _ in EntryItemMetadata(kind: "Fixture", creatorApplication: nil, lastUsedDate: nil) },
        getImageResolution: { _ in nil },
        getFileSizeInBytes: { _ in nil },
        getFolderItemCount: { _ in nil },
        isPackageDirectory: { _ in false },
        displayName: { path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return name.isEmpty ? path : name
        },
    )
}

private enum FileManagerHostFixtureSampleData {
    static let path = "/Fixture/FileManager"

    static let entries: [EntryModel] = [
        makeEntry(name: "Projects", isFolder: true, size: 0, kind: "Folder"),
        makeEntry(
            name: "Voyager Notes.md",
            isFolder: false,
            size: 24576,
            kind: "Markdown Document",
            fileExtension: "md",
        ),
        makeEntry(
            name: "Design Reference.png",
            isFolder: false,
            size: 1_572_864,
            kind: "PNG Image",
            fileExtension: "png",
        ),
    ]

    private static let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)

    private static func makeEntry(
        name: String,
        isFolder: Bool,
        size: Int64,
        kind: String,
        fileExtension: String = "",
    ) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: "\(path)/\(name)",
            isFolder: isFolder,
            isHidden: false,
            size: size,
            modifiedDate: referenceDate,
            fileExtension: fileExtension,
            facets: EntryFacets(
                createdDate: referenceDate,
                addedDate: referenceDate,
                lastOpenedDate: nil,
                kind: kind,
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
