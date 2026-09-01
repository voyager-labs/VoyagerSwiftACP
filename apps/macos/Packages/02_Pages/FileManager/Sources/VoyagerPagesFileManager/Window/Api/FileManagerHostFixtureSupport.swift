import Foundation
import VoyagerEntitiesEntry
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

private typealias FileManagerHostStagedEntryLoader = @Sendable (
    URL,
    Bool,
    EntryMetadataPriority,
) -> AsyncThrowingStream<EntryLoadEvent, Error>

extension EntryLoadingClient {
    static func fileManagerHostFixture(
        scenario: FileManagerHostScenario,
        preset: String?,
        windowID: UUID,
    ) -> EntryLoadingClient {
        let rootEntries = FileManagerHostFixtureSampleData.rootEntries(
            for: preset.flatMap(FileManagerHostPreset.init(rawValue:)),
        )
        let progressiveLoadingCoordinator = FileManagerHostFixtureProgressiveLoadingCoordinator()
        let stagedLoadItems = stagedEntryLoader(
            scenario: scenario,
            preset: preset,
            windowID: windowID,
            coordinator: progressiveLoadingCoordinator,
        )

        return EntryLoadingClient(
            loadItems: { directoryURL, _ in
                fixtureEntries(for: directoryURL, scenario: scenario, rootEntries: rootEntries)
            },
            loadComputerItems: { rootEntries },
            loadRecentItems: { _, _ in rootEntries },
            loadFilesWithTag: { _, _, _ in rootEntries },
            fileExists: { _ in false },
            fileExistsAtPath: { _, _ in false },
            contentsOfDirectory: { _, _, _ in [] },
            mountedVolumeURLs: { _, _ in nil },
            urlsForDirectory: { directory, _ in fixtureURLs(for: directory) },
            homeDirectory: { "/Fixture" },
            getItemMetadata: { _, _, _ in
                EntryItemMetadata(kind: "Fixture", creatorApplication: nil, lastUsedDate: nil)
            },
            getImageResolution: { _ in nil },
            getFileSizeInBytes: { _ in nil },
            getFolderItemCount: { url in
                scenario.largeFolder != .none
                    && url.path == FileManagerHostFixtureSampleData.largeFolder.fullPath
                    ? FileManagerHostFixtureSampleData.largeFolderEntries.count
                    : nil
            },
            isPackageDirectory: { _ in false },
            displayName: { path in
                let name = URL(fileURLWithPath: path).lastPathComponent
                return name.isEmpty ? path : name
            },
            stagedLoadItems: stagedLoadItems,
        )
    }

    private static func stagedEntryLoader(
        scenario: FileManagerHostScenario,
        preset: String?,
        windowID: UUID,
        coordinator: FileManagerHostFixtureProgressiveLoadingCoordinator,
    ) -> FileManagerHostStagedEntryLoader? {
        let rootEntries = FileManagerHostFixtureSampleData.rootEntries(
            for: preset.flatMap(FileManagerHostPreset.init(rawValue:)),
        )
        guard scenario.progressiveEntryLoading != .none
            || scenario.delayedNavigation != .none
            || scenario.permission != .none
            || scenario.largeFolder != .none
        else { return nil }
        return { directoryURL, _, _ in
            guard isScenarioFolder(directoryURL, scenario: scenario) else {
                return immediateStream(entries: fixtureEntries(
                    for: directoryURL,
                    scenario: scenario,
                    rootEntries: rootEntries,
                ))
            }
            let request = coordinator.beginRequest()
            let shouldDenyPermission = directoryURL.path == FileManagerHostFixtureSampleData.restrictedFolder.fullPath
                && (scenario.permission == .denied || coordinator.beginPermissionAttempt() == 1)
            return FileManagerHostFixtureProgressiveLoading.stream(
                scenario: scenario,
                preset: preset,
                requestID: request,
                windowID: windowID,
                shouldDenyPermission: shouldDenyPermission,
                isCurrent: { coordinator.isCurrent(request) },
            )
        }
    }

    private static func fixtureEntries(
        for directoryURL: URL,
        scenario: FileManagerHostScenario,
        rootEntries: [EntryModel],
    ) -> [EntryModel] {
        switch directoryURL.path {
        case FileManagerHostFixtureSampleData.restrictedFolder.fullPath:
            FileManagerHostFixtureSampleData.permissionChildren
        case FileManagerHostFixtureSampleData.largeFolder.fullPath:
            FileManagerHostFixtureSampleData.largeFolderEntries
        case FileManagerHostFixtureSampleData.projects.fullPath:
            FileManagerHostFixtureSampleData.progressiveChildren
        case FileManagerHostFixtureSampleData.materialDesignAssets.fullPath:
            FileManagerHostFixtureSampleData.materialDesignAssetEntries
        case FileManagerHostFixtureSampleData.siblingFolder.fullPath:
            []
        case FileManagerHostFixtureSampleData.path:
            if scenario.permission != .none {
                FileManagerHostFixtureSampleData.permissionEntries
            } else if scenario.largeFolder != .none {
                FileManagerHostFixtureSampleData.largeFolderRootEntries
            } else {
                rootEntries
            }
        default:
            rootEntries
        }
    }

    private static func isScenarioFolder(_ directoryURL: URL, scenario: FileManagerHostScenario) -> Bool {
        if scenario.permission != .none {
            return directoryURL.path == FileManagerHostFixtureSampleData.restrictedFolder.fullPath
        }
        if scenario.largeFolder != .none {
            return directoryURL.path == FileManagerHostFixtureSampleData.largeFolder.fullPath
        }
        if scenario.delayedNavigation != .none {
            return true
        }
        if scenario.progressiveEntryLoading != .none {
            return directoryURL.path == FileManagerHostFixtureSampleData.projects.fullPath
        }
        return false
    }

    private static func immediateStream(entries: [EntryModel]) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.coreBatch(items: entries, batchIndex: 0))
            continuation.yield(.coreFinished(batchCount: 1))
            continuation.finish()
        }
    }

    private static func fixtureURLs(for directory: FileManager.SearchPathDirectory) -> [URL] {
        switch directory {
        case .desktopDirectory: [URL(fileURLWithPath: "/Fixture/Desktop")]
        case .documentDirectory: [URL(fileURLWithPath: "/Fixture/Documents")]
        case .downloadsDirectory: [URL(fileURLWithPath: "/Fixture/Downloads")]
        case .applicationDirectory: [URL(fileURLWithPath: "/Fixture/Applications")]
        case .trashDirectory: [URL(fileURLWithPath: "/Fixture/.Trash")]
        default: []
        }
    }
}

enum FileManagerHostFixtureSampleData {
    static let path = "/Fixture/FileManager"
    static let delayedRootPath = "/Fixture/FileManager/Delayed Root"
    static let delayedRootReplacementPath = "/Fixture/FileManager/Replacement Root"
    static let delayedTabPrimaryPath = "/Fixture/FileManager/Delayed Tab Primary"
    static let delayedTabSecondaryPath = "/Fixture/FileManager/Delayed Tab Secondary"

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

    static let materialCatalogEntries: [EntryModel] = [
        makeEntry(name: "Projects", isFolder: true, size: 0, kind: "Folders"),
        materialDesignAssets,
        makeEntry(
            name: "Portable Document.pdf",
            isFolder: false,
            size: 842_752,
            kind: "Documents",
            fileExtension: "pdf",
        ),
        makeEntry(name: "Word Document.docx", isFolder: false, size: 61440, kind: "Documents", fileExtension: "docx"),
        makeEntry(name: "Rich Text.rtf", isFolder: false, size: 18432, kind: "Documents", fileExtension: "rtf"),
        makeEntry(name: "Hangul Document.hwp", isFolder: false, size: 132_096, kind: "Documents", fileExtension: "hwp"),
        makeEntry(name: "Workbook.xlsx", isFolder: false, size: 95232, kind: "Spreadsheets", fileExtension: "xlsx"),
        makeEntry(
            name: "Legacy Workbook.xls",
            isFolder: false,
            size: 73728,
            kind: "Spreadsheets",
            fileExtension: "xls",
        ),
        makeEntry(
            name: "Comma-Separated.csv",
            isFolder: false,
            size: 12288,
            kind: "Spreadsheets",
            fileExtension: "csv",
        ),
        makeEntry(
            name: "Macro Workbook.xlsm",
            isFolder: false,
            size: 108_544,
            kind: "Spreadsheets",
            fileExtension: "xlsm",
        ),
        makeEntry(name: "Reference.png", isFolder: false, size: 1_572_864, kind: "Images", fileExtension: "png"),
        makeEntry(name: "Photograph.jpg", isFolder: false, size: 2_621_440, kind: "Images", fileExtension: "jpg"),
        makeEntry(name: "Animation.gif", isFolder: false, size: 786_432, kind: "Images", fileExtension: "gif"),
        makeEntry(name: "Scanned.tiff", isFolder: false, size: 4_194_304, kind: "Images", fileExtension: "tiff"),
        makeEntry(name: "Interview.mp3", isFolder: false, size: 8_388_608, kind: "Media", fileExtension: "mp3"),
        makeEntry(name: "Lossless Audio.wav", isFolder: false, size: 25_165_824, kind: "Media", fileExtension: "wav"),
        makeEntry(name: "Product Demo.mp4", isFolder: false, size: 67_108_864, kind: "Media", fileExtension: "mp4"),
        makeEntry(name: "Screen Recording.mov", isFolder: false, size: 92_274_688, kind: "Media", fileExtension: "mov"),
        makeEntry(name: "Release.zip", isFolder: false, size: 5_242_880, kind: "Archives", fileExtension: "zip"),
        makeEntry(name: "Backup.7z", isFolder: false, size: 12_582_912, kind: "Archives", fileExtension: "7z"),
        makeEntry(name: "Source.tar.gz", isFolder: false, size: 3_145_728, kind: "Archives", fileExtension: "gz"),
    ]

    static let materialDesignAssets = makeEntry(name: "Design Assets", isFolder: true, size: 0, kind: "Folders")

    static let materialDesignAssetEntries = [
        makeEntry(
            name: "Design Asset Preview.png",
            isFolder: false,
            size: 1_572_864,
            kind: "Images",
            fileExtension: "png",
            parentPath: materialDesignAssets.fullPath,
        ),
    ]

    static let materialDocumentEntries = materialCatalogEntries.filter {
        ["Documents", "Spreadsheets"].contains($0.facets.kind)
    }

    static let materialMediaEntries = materialCatalogEntries.filter {
        ["Images", "Media"].contains($0.facets.kind)
    }

    static let materialStressEntries: [EntryModel] = [
        makeEntry(
            name: "매우 긴 한국어 파일 이름과 여러 단어가 포함된 최종 검토 문서.pdf",
            isFolder: false,
            size: 524_288,
            kind: "Long Names",
            fileExtension: "pdf",
        ),
        makeEntry(
            name: "Résumé final avec caractères accentués.docx",
            isFolder: false,
            size: 81920,
            kind: "Long Names",
            fileExtension: "docx",
        ),
        makeEntry(
            name: "2026-08-31T23-59-59Z-production-export-with-a-very-long-suffix.json",
            isFolder: false,
            size: 16384,
            kind: "Long Names",
            fileExtension: "json",
        ),
        makeEntry(name: ".voyager-fixture", isFolder: false, size: 256, kind: "Edge Cases"),
        makeEntry(name: "README", isFolder: false, size: 4096, kind: "Edge Cases"),
        makeEntry(name: "Empty File.txt", isFolder: false, size: 0, kind: "Edge Cases", fileExtension: "txt"),
    ]

    static let projects = makeEntry(name: "Projects", isFolder: true, size: 0, kind: "Folder")

    static let restrictedFolder = makeEntry(name: "Restricted", isFolder: true, size: 0, kind: "Restricted Folder")
    static let siblingFolder = makeEntry(name: "Sibling", isFolder: true, size: 0, kind: "Folder")
    static let permissionEntries = [restrictedFolder, siblingFolder]
    static let permissionChildren = [
        makeEntry(
            name: "Allowed sibling.txt",
            isFolder: false,
            size: 1024,
            kind: "Text Document",
            fileExtension: "txt",
            parentPath: restrictedFolder.fullPath,
        ),
    ]

    static let largeFolder = makeEntry(name: "Large Folder", isFolder: true, size: 0, kind: "Folder")
    static let largeFolderRootEntries = [largeFolder]

    static let largeFolderEntries: [EntryModel] = (1 ... 1000).map { index in
        makeEntry(
            name: String(format: "Large Item %04d.dat", index),
            isFolder: false,
            size: Int64(index * 128),
            kind: "Data File",
            fileExtension: "dat",
            parentPath: largeFolder.fullPath,
        )
    }

    static let collectionEntries: [EntryModel] = (1 ... 3).map { index in
        makeEntry(
            name: "Collection Result \(index)",
            isFolder: false,
            size: Int64(index * 512),
            kind: "Collection Result",
            fileExtension: "txt",
            parentPath: "/Fixture/Collection Results",
        )
    }

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

    static func rootEntries(for preset: FileManagerHostPreset?) -> [EntryModel] {
        switch preset {
        case .permissionDenied, .permissionRetry:
            permissionEntries
        case .largeFolder1000, .concurrentLargeFolders:
            largeFolderRootEntries
        case .materialTuning:
            materialCatalogEntries
        case .fixtureDocuments:
            materialDocumentEntries
        case .fixtureMedia:
            materialMediaEntries
        case .fixtureStress:
            materialStressEntries
        default:
            entries
        }
    }

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

enum FileManagerHostFixturePhase: String {
    case waiting
    case firstBatch
    case coreFinished
    case streamFinished
    case partialFailure
    case cancelled
    case permissionDenied
    case retryStarted
    case retrySucceeded
    case collectionStarted
    case collectionFinished

    func log(count: Int, windowID: UUID) {
        log(preset: nil, windowID: windowID, requestID: nil, errorCode: nil, rowCount: nil, count: count)
    }

    func log(
        preset: String?,
        windowID: UUID,
        requestID: UUID? = nil,
        errorCode: Int? = nil,
        rowCount: Int? = nil,
        count: Int = 0,
    ) {
        let metadata = [
            preset.map { "preset=\($0)" },
            requestID.map { "requestID=\($0.uuidString)" },
            errorCode.map { "errorCode=\($0)" },
            rowCount.map { "rowCount=\($0)" },
        ].compactMap(\.self).joined(separator: " ")
        print("[FileManagerHostFixture] \(rawValue):\(count) windowID=\(windowID.uuidString) \(metadata)")
        var userInfo: [AnyHashable: Any] = [
            FileManagerHostFixture.phaseUserInfoKey: rawValue,
            FileManagerHostFixture.phaseWindowIDUserInfoKey: windowID,
        ]
        if let preset { userInfo[FileManagerHostFixture.phasePresetUserInfoKey] = preset }
        if let requestID { userInfo[FileManagerHostFixture.phaseRequestIDUserInfoKey] = requestID }
        if let errorCode { userInfo[FileManagerHostFixture.phaseErrorCodeUserInfoKey] = errorCode }
        if let rowCount { userInfo[FileManagerHostFixture.phaseRowCountUserInfoKey] = rowCount }
        NotificationCenter.default.post(
            name: FileManagerHostFixture.phaseDidChange,
            object: nil,
            userInfo: userInfo,
        )
    }
}

private enum FileManagerHostFixtureProgressiveLoadingError: Error {
    case partialFailure
}

private final class FileManagerHostFixtureProgressiveLoadingCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var latestRequest = 0
    private var permissionAttempts = 0

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

    func beginPermissionAttempt() -> Int {
        lock.lock()
        defer { lock.unlock() }
        permissionAttempts += 1
        return permissionAttempts
    }
}

private enum FileManagerHostFixtureProgressiveLoading {
    private struct FileManagerHostEntryStreamContext {
        let preset: String?
        let windowID: UUID
        let isCurrent: @Sendable () -> Bool
        let continuation: AsyncThrowingStream<EntryLoadEvent, Error>.Continuation
    }

    static func stream(
        scenario: FileManagerHostScenario,
        preset: String?,
        requestID: Int,
        windowID: UUID,
        shouldDenyPermission: Bool = false,
        isCurrent: @escaping @Sendable () -> Bool,
    ) -> AsyncThrowingStream<EntryLoadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await runStream(
                    scenario: scenario,
                    requestID: requestID,
                    shouldDenyPermission: shouldDenyPermission,
                    context: FileManagerHostEntryStreamContext(
                        preset: preset,
                        windowID: windowID,
                        isCurrent: isCurrent,
                        continuation: continuation,
                    ),
                )
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func runStream(
        scenario: FileManagerHostScenario,
        requestID: Int,
        shouldDenyPermission: Bool,
        context: FileManagerHostEntryStreamContext,
    ) async {
        do {
            try await produceStream(
                scenario: scenario,
                requestID: requestID,
                shouldDenyPermission: shouldDenyPermission,
                context: context,
            )
        } catch is CancellationError {
            context.continuation.finish()
        } catch {
            context.continuation.finish(throwing: error)
        }
    }

    private static func produceStream(
        scenario: FileManagerHostScenario,
        requestID: Int,
        shouldDenyPermission: Bool,
        context: FileManagerHostEntryStreamContext,
    ) async throws {
        let notificationRequestID = requestUUID(
            scenario: scenario,
            requestID: requestID,
            windowID: context.windowID,
        )
        if try await finishIfStreamCancelled(
            milliseconds: 100,
            notificationRequestID: notificationRequestID,
            context: context,
        ) { return }
        FileManagerHostFixturePhase.waiting.log(
            preset: context.preset,
            windowID: context.windowID,
            requestID: notificationRequestID,
        )
        if try await finishIfStreamCancelled(
            milliseconds: 300,
            notificationRequestID: notificationRequestID,
            context: context,
        ) { return }

        if scenario.permission != .none {
            return try await producePermissionStream(
                shouldDenyPermission: shouldDenyPermission,
                notificationRequestID: notificationRequestID,
                context: context,
            )
        }

        try await produceProgressiveStream(
            scenario: scenario,
            notificationRequestID: notificationRequestID,
            context: context,
        )
    }

    private static func produceProgressiveStream(
        scenario: FileManagerHostScenario,
        notificationRequestID: UUID,
        context: FileManagerHostEntryStreamContext,
    ) async throws {
        let children = scenario.largeFolder == .none
            ? FileManagerHostFixtureSampleData.progressiveChildren
            : FileManagerHostFixtureSampleData.largeFolderEntries
        let firstBatchCount = min(32, children.count)
        context.continuation.yield(.coreBatch(items: Array(children.prefix(firstBatchCount)), batchIndex: 0))
        FileManagerHostFixturePhase.firstBatch.log(
            preset: context.preset,
            windowID: context.windowID,
            requestID: notificationRequestID,
            rowCount: children.count,
            count: firstBatchCount,
        )
        guard scenario.progressiveEntryLoading != .partialFailure else {
            FileManagerHostFixturePhase.partialFailure.log(
                preset: context.preset,
                windowID: context.windowID,
                requestID: notificationRequestID,
                rowCount: firstBatchCount,
                count: firstBatchCount,
            )
            throw FileManagerHostFixtureProgressiveLoadingError.partialFailure
        }

        try await finishEntryStream(
            children: children,
            firstBatchCount: firstBatchCount,
            notificationRequestID: notificationRequestID,
            context: context,
        )
    }

    private static func finishIfStreamCancelled(
        milliseconds: UInt64,
        notificationRequestID: UUID,
        context: FileManagerHostEntryStreamContext,
    ) async throws -> Bool {
        try await Task.sleep(for: .milliseconds(milliseconds))
        guard context.isCurrent() else {
            FileManagerHostFixturePhase.cancelled.log(
                preset: context.preset,
                windowID: context.windowID,
                requestID: notificationRequestID,
            )
            context.continuation.finish()
            return true
        }
        return false
    }

    private static func producePermissionStream(
        shouldDenyPermission: Bool,
        notificationRequestID: UUID,
        context: FileManagerHostEntryStreamContext,
    ) async throws {
        if shouldDenyPermission {
            FileManagerHostFixturePhase.permissionDenied.log(
                preset: context.preset,
                windowID: context.windowID,
                requestID: notificationRequestID,
                errorCode: NSFileReadNoPermissionError,
            )
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        }
        FileManagerHostFixturePhase.retryStarted.log(
            preset: context.preset,
            windowID: context.windowID,
            requestID: notificationRequestID,
        )
        let children = FileManagerHostFixtureSampleData.permissionChildren
        context.continuation.yield(.coreBatch(items: children, batchIndex: 0))
        context.continuation.yield(.coreFinished(batchCount: 1))
        FileManagerHostFixturePhase.retrySucceeded.log(
            preset: context.preset,
            windowID: context.windowID,
            requestID: notificationRequestID,
            rowCount: children.count,
            count: children.count,
        )
        context.continuation.finish()
    }

    private static func finishEntryStream(
        children: [EntryModel],
        firstBatchCount: Int,
        notificationRequestID: UUID,
        context: FileManagerHostEntryStreamContext,
    ) async throws {
        try await Task.sleep(for: .milliseconds(300))
        guard context.isCurrent() else {
            FileManagerHostFixturePhase.cancelled.log(
                preset: context.preset,
                windowID: context.windowID,
                requestID: notificationRequestID,
            )
            return context.continuation.finish()
        }
        var nextBatchIndex = 1
        var offset = firstBatchCount
        while offset < children.count {
            let end = min(offset + 32, children.count)
            context.continuation.yield(.coreBatch(items: Array(children[offset ..< end]), batchIndex: nextBatchIndex))
            nextBatchIndex += 1
            offset = end
        }
        context.continuation.yield(.coreFinished(batchCount: nextBatchIndex))
        FileManagerHostFixturePhase.coreFinished.log(
            preset: context.preset,
            windowID: context.windowID,
            requestID: notificationRequestID,
            rowCount: children.count,
            count: children.count,
        )
        try await Task.sleep(for: .milliseconds(300))
        guard context.isCurrent() else {
            FileManagerHostFixturePhase.cancelled.log(
                preset: context.preset,
                windowID: context.windowID,
                requestID: notificationRequestID,
            )
            return context.continuation.finish()
        }
        context.continuation.yield(.metadataPatches(children.map {
            .spotlight(
                id: $0.id,
                kind: "Fixture Text Document",
                creatorApplication: nil,
                lastOpenedDate: nil,
            )
        }))
        context.continuation.finish()
        FileManagerHostFixturePhase.streamFinished.log(
            preset: context.preset,
            windowID: context.windowID,
            requestID: notificationRequestID,
            rowCount: children.count,
            count: children.count,
        )
    }

    private static func requestUUID(scenario: FileManagerHostScenario, requestID: Int, windowID: UUID) -> UUID {
        let rawValue = scenario.largeFolder == .concurrent
            ? "00000000-0000-0000-0000-\(windowID.uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
            : String(format: "00000000-0000-0000-0000-%012d", requestID)
        return UUID(uuidString: rawValue) ?? UUID()
    }
}
