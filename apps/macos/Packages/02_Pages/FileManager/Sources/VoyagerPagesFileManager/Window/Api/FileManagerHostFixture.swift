import AppKit
import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@MainActor
public enum FileManagerHostFixture {
    public static func makeWindowController(
        preset: FileManagerHostPreset = .default,
    ) -> NSWindowController {
        let state = FileManagerHostFixtureStateFactory.makeState()
        let undoManager = UndoManager()
        let store = Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            FileManagerHostFixtureDependencies.apply(to: &$0, undoManager: undoManager)
        }

        return FileManagerWindowCoordinator(
            windowID: UUID(),
            store: store,
            windowUndoManager: undoManager,
            sessionLapseGuardStore: FileManagerHostFixture.makeSessionLapseGuardStore(
                for: preset.scenario.sessionLapse,
            ),
        )
    }

    /// ponytail: AccountAccess 의존성은 모두 안전한 no-op previewValue로 주입.
    static func makeSessionLapseGuardStore(
        for scenario: FileManagerHostSessionLapseScenario,
    ) -> Store<AccountAccessFeature.State?, AccountAccessAction>? {
        switch scenario {
        case .none:
            return nil
        case .active, .signInFailed:
            var guardState: AccountAccessFeature.State? = AccountAccessFeature.State()
            if scenario == .signInFailed {
                guardState?.didSignInFail = true
            }
            return Store<AccountAccessFeature.State?, AccountAccessAction>(
                initialState: guardState,
            ) {
                EmptyReducer()
            }
        }
    }
}

@MainActor
private enum FileManagerHostFixtureStateFactory {
    static func makeState() -> FileManagerFeature.State {
        var state = FileManagerFeature.State.makeInitial(path: FileManagerHostFixtureSampleData.path)
        state.sidebar.sidebarVisible = true
        state.sidebar.sidebarWidth = 220
        state.sidebar.favorites = FileManagerHostFixtureSampleData.favorites
        state.sidebar.locations = FileManagerHostFixtureSampleData.locations
        state.sidebar.tags = FileManagerHostFixtureSampleData.finderTags
        state.sidebar.selectedSidebarItem = "Recents"
        state.content.entryViewLayout.currentPath = FileManagerHostFixtureSampleData.path
        state.content.entryViewLayout.mode = .list
        state.content.entryViewLayout.entryOperations.items = IdentifiedArrayOf(
            uniqueElements: FileManagerHostFixtureSampleData.entries,
        )
        state.content.entryViewLayout.entries = FileManagerHostFixtureSampleData.entries
        return state
    }
}

@MainActor
private enum FileManagerHostFixtureDependencies {
    static func apply(to dependencies: inout DependencyValues, undoManager: UndoManager) {
        dependencies.userDefaultsClient = .previewValue
        dependencies.metricsClient = .previewValue
        dependencies.fileManagerWindowClient = .previewValue
        dependencies.fileManagerIconClient = .previewValue
        dependencies.fileManagerFavoritesClient = FileManagerFavoritesClient(
            loadFavorites: { _, _ in FileManagerHostFixtureSampleData.favorites },
            saveFavorites: { _, _ in },
        )
        dependencies.fileManagerLocationsClient = FileManagerLocationsClient(
            loadLocations: { _ in FileManagerHostFixtureSampleData.locations },
        )
        dependencies.finderFavoritesTagClient = FinderFavoritesTagClient(
            favoriteTagNames: { FileManagerHostFixtureSampleData.finderTags.map(\.name) },
            favoriteTags: { FileManagerHostFixtureSampleData.finderTags },
        )
        dependencies.entryLoadingClient = .fileManagerHostFixture
        dependencies.fileManagerClient = .previewValue
        dependencies.notificationCenterClient = .previewValue
        dependencies.entryOpenClient = .previewValue
        dependencies.entryQuickLookClient = .previewValue
        dependencies.entryFileOpsClient = .previewValue
        dependencies.entryOperationsAlertClient = .previewValue
        dependencies.undoManagerClient = .live(undoManager: undoManager)
        dependencies.registryClient = .testValue
        dependencies.collectionFileClient = .testValue
        dependencies.collectionAlertClient = .previewValue
        dependencies.collectionSavePanelClient = .previewValue
        dependencies.searchClient = .testValue
        dependencies.composerMetricClient = .testValue
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

    static let favorites: [SidebarItems.FavoriteItem] = [
        .init(name: "Desktop", url: URL(fileURLWithPath: "/Fixture/Desktop"), iconName: "menubar.dock.rectangle"),
        .init(name: "Documents", url: URL(fileURLWithPath: "/Fixture/Documents"), iconName: "doc"),
        .init(name: "Downloads", url: URL(fileURLWithPath: "/Fixture/Downloads"), iconName: "arrow.down.circle"),
    ]

    static let locations: [SidebarItems.LocationItem] = [
        .init(name: "Fixture Disk", url: URL(fileURLWithPath: "/Fixture"), iconName: "internaldrive"),
    ]

    static let finderTags: [Tag] = [
        .init(name: "Design", colorCode: 2),
        .init(name: "Review", colorCode: 4),
    ]

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
