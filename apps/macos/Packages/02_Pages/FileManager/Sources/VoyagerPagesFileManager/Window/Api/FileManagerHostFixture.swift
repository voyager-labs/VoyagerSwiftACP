import AppKit
import ComposableArchitecture
import Foundation
import IdentifiedCollections
import UniformTypeIdentifiers
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAccountAccess
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

    nonisolated public static let phaseDidChange = Notification.Name("FileManagerHostFixture.phaseDidChange")
    nonisolated public static let phaseUserInfoKey = "phase"
    nonisolated public static let phaseWindowIDUserInfoKey = "windowID"

    public static func makeWindowController(
        preset: FileManagerHostPreset = .default,
        oneDriveIcon: @escaping @Sendable () -> NSImage? = { nil },
        onBecameKey: (@MainActor (UUID) -> Void)? = nil,
        onWillClose: (@MainActor (UUID) -> Void)? = nil,
        materialConfiguration: MaterialConfiguration? = nil,
    ) -> FileManagerWindowCoordinator {
        let windowID = UUID()
        let state = FileManagerHostFixtureStateFactory.makeState(preset: preset)
        let fileOperationUndoManagerRegistry = FileOperationUndoManagerRegistry()
        let workspaceClient = WorkspaceClient.fileManagerHostFixture(oneDriveIcon: oneDriveIcon)
        let store = Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            FileManagerHostFixtureDependencies.apply(
                to: &$0,
                undoManager: UndoManager(),
                progressiveEntryLoading: preset.scenario.progressiveEntryLoading,
                windowID: windowID,
                workspaceClient: workspaceClient,
            )
        }

        return FileManagerWindowCoordinator(
            windowID: windowID,
            store: store,
            fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
            workspaceClient: workspaceClient,
            sessionLapseGuardStore: FileManagerHostFixture.makeSessionLapseGuardStore(
                for: preset.scenario.sessionLapse,
            ),
            onBecameKey: onBecameKey,
            onWillClose: onWillClose,
            materialOverride: materialConfiguration?.materialOverride,
        )
    }

    public static func updateMaterialConfiguration(
        _ materialConfiguration: MaterialConfiguration?,
        in coordinator: FileManagerWindowCoordinator,
    ) {
        coordinator.updateMaterialOverride(materialConfiguration?.materialOverride)
    }

    /// Host window가 mount된 뒤 fixture Projects folder의 deterministic stream을 시작한다.
    public static func startScenarioIfNeeded(
        for preset: FileManagerHostPreset,
        in windowController: FileManagerWindowCoordinator,
    ) {
        guard preset.scenario.progressiveEntryLoading != .none else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            windowController.store.send(
                .content(
                    .entryViewLayout(
                        .hierarchy(
                            .folderExpansionRequested(id: FileManagerHostFixtureSampleData.projects.id),
                        ),
                    ),
                ),
            )
        }
    }

    static func makeState(preset: FileManagerHostPreset) -> FileManagerFeature.State {
        FileManagerHostFixtureStateFactory.makeState(preset: preset)
    }

    static func applyDependencies(
        to dependencies: inout DependencyValues,
        undoManager: UndoManager,
        progressiveEntryLoading: FileManagerHostProgressiveEntryLoadingScenario,
        windowID: UUID,
        workspaceClient: WorkspaceClient,
    ) {
        FileManagerHostFixtureDependencies.apply(
            to: &dependencies,
            undoManager: undoManager,
            progressiveEntryLoading: progressiveEntryLoading,
            windowID: windowID,
            workspaceClient: workspaceClient,
        )
    }

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
    static func makeState(preset _: FileManagerHostPreset) -> FileManagerFeature.State {
        var state = FileManagerFeature.State.makeInitial(path: nil)
        state.sidebar.sidebarVisible = true
        state.sidebar.sidebarWidth = 220
        state.content.navigation.seedInitialFolderPath(FileManagerHostFixtureSampleData.path)
        state.content.entryViewLayout.mode = .list
        state.content.entryViewLayout.hierarchy.replaceRoot(path: FileManagerHostFixtureSampleData.path)
        state.content.entryViewLayout.entryOperations.items = IdentifiedArrayOf(
            uniqueElements: FileManagerHostFixtureSampleData.entries,
        )
        state.content.entryViewLayout.entries = FileManagerHostFixtureSampleData.entries
        return state
    }
}

@MainActor
enum FileManagerHostFixtureDependencies {
    static func apply(
        to dependencies: inout DependencyValues,
        undoManager _: UndoManager,
        progressiveEntryLoading: FileManagerHostProgressiveEntryLoadingScenario,
        windowID _: UUID,
        workspaceClient: WorkspaceClient,
    ) {
        dependencies.userDefaultsClient = .previewValue
        dependencies.metricsClient = .previewValue
        dependencies.fileManagerWindowClient = .previewValue
        dependencies.fileManagerIconClient = .previewValue
        dependencies.entryLoadingClient = .fileManagerHostFixture(
            progressiveEntryLoading: progressiveEntryLoading,
        )
        dependencies.fileManagerClient = .previewValue
        dependencies.fileManagerLocationsClient = .fileManagerHostFixture
        dependencies.notificationCenterClient = .previewValue
        dependencies.workspaceClient = workspaceClient
        dependencies.entryOpenClient = .previewValue
        dependencies.entryQuickLookClient = .previewValue
        dependencies.entryFileOpsClient = .previewValue
        dependencies.entryOperationsAlertClient = .previewValue
        dependencies.fileOperationUndoManagerClient = .live(registry: FileOperationUndoManagerRegistry())
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
    static func fileManagerHostFixture(
        progressiveEntryLoading: FileManagerHostProgressiveEntryLoadingScenario,
    ) -> EntryLoadingClient {
        let progressiveLoadingCoordinator = FileManagerHostFixtureProgressiveLoadingCoordinator()
        let stagedLoadItems: (@Sendable (URL, Bool, EntryMetadataPriority) -> AsyncThrowingStream<
            EntryLoadEvent,
            Error,
        >)? = if progressiveEntryLoading == .none {
            nil
        } else {
            { _, _, _ in
                let request = progressiveLoadingCoordinator.beginRequest()
                return FileManagerHostFixtureProgressiveLoading.stream(
                    for: progressiveEntryLoading,
                    isCurrent: { progressiveLoadingCoordinator.isCurrent(request) },
                )
            }
        }

        return EntryLoadingClient(
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
            getItemMetadata: { _, _, _ in
                EntryItemMetadata(kind: "Fixture", creatorApplication: nil, lastUsedDate: nil)
            },
            getImageResolution: { _ in nil },
            getFileSizeInBytes: { _ in nil },
            getFolderItemCount: { _ in nil },
            isPackageDirectory: { _ in false },
            displayName: { path in
                let name = URL(fileURLWithPath: path).lastPathComponent
                return name.isEmpty ? path : name
            },
            stagedLoadItems: stagedLoadItems,
        )
    }
}

private enum FileManagerHostFixtureSampleData {
    static let path = "/Fixture/FileManager"

    static let entries: [EntryModel] = [
        projects,
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

    static let projects = makeEntry(name: "Projects", isFolder: true, size: 0, kind: "Folder")

    static let progressiveChildren: [EntryModel] = (1 ... 65).map { index in
        makeEntry(
            name: String(format: "Project Item %03d.txt", index),
            isFolder: false,
            size: Int64(index * 1024),
            kind: "Text Document",
            fileExtension: "txt",
            parentPath: projects.fullPath,
        )
    }

    private static let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)

    private static func makeEntry(
        name: String,
        isFolder: Bool,
        size: Int64,
        kind: String,
        fileExtension: String = "",
        parentPath: String = path,
    ) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: "\(parentPath)/\(name)",
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

private enum FileManagerHostFixturePhase: String {
    case waiting
    case firstBatch
    case coreFinished
    case streamFinished
    case partialFailure

    func log(count: Int) {
        print("[FileManagerHostFixture] \(rawValue):\(count)")
        NotificationCenter.default.post(
            name: FileManagerHostFixture.phaseDidChange,
            object: nil,
            userInfo: [FileManagerHostFixture.phaseUserInfoKey: rawValue],
        )
    }
}

private enum FileManagerHostFixtureProgressiveLoadingError: Error {
    case partialFailure
}

private final class FileManagerHostFixtureProgressiveLoadingCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var latestRequest = 0

    func beginRequest() -> Int {
        lock.lock()
        defer { lock.unlock() }
        latestRequest += 1
        return latestRequest
    }

    func isCurrent(_ request: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return request == latestRequest
    }
}

private enum FileManagerHostFixtureProgressiveLoading {
    static func stream(
        for scenario: FileManagerHostProgressiveEntryLoadingScenario,
        isCurrent: @escaping @Sendable () -> Bool,
    ) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                    guard isCurrent() else {
                        continuation.finish()
                        return
                    }
                    FileManagerHostFixturePhase.waiting.log(count: 0)
                    try await Task.sleep(for: .milliseconds(300))

                    guard isCurrent() else {
                        continuation.finish()
                        return
                    }
                    let children = FileManagerHostFixtureSampleData.progressiveChildren
                    continuation.yield(.coreBatch(items: Array(children.prefix(32)), batchIndex: 0))
                    FileManagerHostFixturePhase.firstBatch.log(count: 32)

                    try await Task.sleep(for: .milliseconds(300))
                    guard isCurrent() else {
                        continuation.finish()
                        return
                    }
                    guard scenario == .success else {
                        FileManagerHostFixturePhase.partialFailure.log(count: 32)
                        continuation.finish(throwing: FileManagerHostFixtureProgressiveLoadingError.partialFailure)
                        return
                    }

                    continuation.yield(.coreBatch(items: Array(children.dropFirst(32)), batchIndex: 1))
                    continuation.yield(.coreFinished(batchCount: 2))
                    FileManagerHostFixturePhase.coreFinished.log(count: children.count)

                    try await Task.sleep(for: .milliseconds(300))
                    guard isCurrent() else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(
                        .metadataPatches(
                            children.map {
                                .spotlight(
                                    id: $0.id,
                                    kind: "Fixture Text Document",
                                    creatorApplication: nil,
                                    lastOpenedDate: nil,
                                )
                            },
                        ),
                    )
                    continuation.finish()
                    FileManagerHostFixturePhase.streamFinished.log(count: children.count)
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
