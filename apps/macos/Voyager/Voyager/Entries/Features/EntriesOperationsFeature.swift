import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

// swiftlint:disable type_body_length file_length
/// Entries의 파일 시스템 작업 관리
@Reducer
struct EntriesOperationsFeature {
    struct TagChangeTarget: Equatable, Sendable {
        let file: Entry
        let beforeTags: [String]
        let afterTags: [String]
    }

    @ObservableState
    struct State: Equatable {
        var itemStates: [String: ItemOperationState] = [:]
        var applicationsForItems: [String: [ApplicationInfo]] = [:]
        var commonApplicationsForSelectedFiles: [ApplicationInfo] = []
    }

    struct ItemOperationState: Equatable {
        var isBusy: Bool
        var lastError: FileOpError?

        init(isBusy: Bool = false, lastError: FileOpError? = nil) {
            self.isBusy = isBusy
            self.lastError = lastError
        }
    }

    enum Action: Sendable {
        case openFiles(files: [Entry])
        case quickLookFile(file: Entry)
        case quickLookFiles(files: [Entry])
        case openFileWithApp(file: Entry)
        case openFileWithAppBundleID(filePath: String, bundleID: String, url: URL)
        case setDefaultAppForFile(type: UTType?, bundleID: String, file: Entry)
        case setDefaultAppWithOther(file: Entry)
        case openFilesWithAppFromOther(files: [Entry], shouldSetAsDefault: Bool)
        case loadApplicationsForFile(file: Entry)
        case createNewFolder(name: String, parentPath: String)
        case copySelectedItems(files: [Entry])
        case pasteItems(
            sourcePaths: [String],
            destinationPath: String,
            operation: ClipboardOperation,
            actionKind: EntryActionRecord.ActionKind,
        )
        case renameItem(oldPath: String, newPath: String)
        case moveToTrash(items: [Entry])
        case deleteImmediately(items: [Entry])
        case putBackFromTrash(items: [Entry])
        case emptyTrash(items: [Entry])
        case compressItems(items: [Entry])
        case extractCompressedFile(file: Entry)
        case setTagsForItems(targets: [TagChangeTarget])
        case applicationsLoaded(String, [ApplicationInfo])
        case loadCommonApplicationsForFiles(files: [Entry])
        case commonApplicationsLoaded([ApplicationInfo])
        case operationStarted(String, OperationKind)
        case operationFinished(String, OperationKind, Result<Void, FileOpError>)
        case entryActionCompleted(EntryActionRecord)
        case clearError(String)
    }

    @Dependency(\.entryClient)
    var entryClient
    @Dependency(\.workspaceClient)
    var workspaceClient
    @Dependency(\.entryCapabilities)
    var capabilities

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .clearError(filePath):
                state.itemStates[filePath]?.lastError = nil
                return .none

            case let .operationStarted(filePath, _):
                state.itemStates[filePath] = ItemOperationState(isBusy: true, lastError: nil)
                return .none

            case let .operationFinished(filePath, kind, result):
                state.itemStates[filePath]?.isBusy = false
                switch result {
                case .success:
                    state.itemStates[filePath]?.lastError = nil

                    // 기본 앱 설정 성공 시 앱 목록 재로드
                    if case .setDefaultApp = kind {
                        state.applicationsForItems[filePath] = nil
                        let url = URL(fileURLWithPath: filePath)
                        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        let fileExtension = url.pathExtension
                        guard !isDirectory else { return .none }
                        let fileType = UTType(filenameExtension: fileExtension) ?? .data

                        return loadApplications(for: filePath, url: url, fileType: fileType)
                    }
                case let .failure(error):
                    state.itemStates[filePath]?.lastError = error
                }
                return .none

            case .entryActionCompleted:
                return .none

            case let .openFiles(files):
                guard !files.isEmpty else {
                    return .none
                }

                let entryClient = entryClient
                return .run { [entryClient] send in
                    guard let firstFile = files.first else { return }
                    let firstFilePath = firstFile.fullPath
                    let isTrash = isInTrash(firstFilePath, entryClient: entryClient)

                    if isTrash {
                        for (index, file) in files.enumerated() {
                            let hasMoreFiles = index < files.count - 1
                            _ = await MainActor.run {
                                EntryAlertUtils.showTrashFileAlert(fileName: file.name, hasMoreFiles: hasMoreFiles)
                            }
                        }
                        return
                    }

                    var groupedFiles: [String: [(Entry, Int)]] = [:]
                    for (index, file) in files.enumerated() {
                        let ext = file.fileExtension.lowercased()
                        groupedFiles[ext, default: []].append((file, index))
                    }

                    for (_, groupFiles) in groupedFiles {
                        let urls = groupFiles.map { URL(fileURLWithPath: $0.0.fullPath) }
                        guard let firstURL = urls.first else { continue }

                        let appURL = await Task { @MainActor in
                            let workspace = NSWorkspace.shared
                            return workspace.urlForApplication(toOpen: firstURL)
                        }.value
                        guard let appURL else {
                            for (file, _) in groupFiles {
                                let filePath = file.fullPath
                                let url = URL(fileURLWithPath: filePath)
                                await send(.operationStarted(filePath, .openDefault))
                                do {
                                    try await entryClient.open(url, .defaultApp)
                                    await send(.operationFinished(filePath, .openDefault, .success(())))
                                } catch {
                                    await send(.operationFinished(filePath, .openDefault, .failure(error.fileOpError)))
                                }
                            }
                            continue
                        }

                        for (file, _) in groupFiles {
                            let filePath = file.fullPath
                            await send(.operationStarted(filePath, .openDefault))
                        }

                        do {
                            try await withScopedAccess(urls) {
                                try await Task { @MainActor in
                                    let workspace = NSWorkspace.shared
                                    let configuration = NSWorkspace.OpenConfiguration()
                                    configuration.createsNewApplicationInstance = false
                                    try await workspace.open(
                                        urls,
                                        withApplicationAt: appURL,
                                        configuration: configuration,
                                    )
                                }.value
                            }
                            for (file, _) in groupFiles {
                                let filePath = file.fullPath
                                await send(
                                    .operationFinished(filePath, .openDefault, .success(())),
                                )
                            }
                        } catch {
                            for (file, _) in groupFiles {
                                let filePath = file.fullPath
                                await send(.operationFinished(filePath, .openDefault, .failure(error.fileOpError)))
                            }
                        }
                    }
                }

            case let .quickLookFile(file):
                let filePath = file.fullPath
                let url = URL(fileURLWithPath: filePath)
                return run(for: filePath, kind: .quickLook) {
                    try await entryClient.quickLook(url)
                }

            case let .quickLookFiles(files):
                let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
                let keyPath = files.first?.fullPath ?? "quicklook"
                return run(for: keyPath, kind: .quickLook) {
                    try await entryClient.quickLookFiles(urls)
                }

            case let .openFileWithApp(file):
                return selectApplicationAndOpenFile(for: file, defaultChecked: false, workspaceClient: workspaceClient)

            case let .openFileWithAppBundleID(filePath, bundleID, url):
                if isInTrash(filePath, entryClient: entryClient) {
                    let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                    return .run { _ in
                        _ = await MainActor.run {
                            EntryAlertUtils.showTrashFileAlert(fileName: fileName, hasMoreFiles: false)
                        }
                    }
                }

                return run(for: filePath, kind: .openWithApp(bundleID)) {
                    try await entryClient.open(url, .bundleID(bundleID))
                }

            case let .setDefaultAppForFile(type, bundleID, file):
                if let error = validateDefaultAppSetting(file: file) {
                    state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                    return .none
                }

                let resolvedType = type ?? UTType(filenameExtension: file.fileExtension)
                guard let fileType = resolvedType else {
                    state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: .unsupportedType)
                    return .none
                }
                let filePath = file.fullPath
                return run(for: filePath, kind: .setDefaultApp(bundleID)) {
                    try await entryClient.setDefaultApp(fileType, bundleID)
                }

            case let .setDefaultAppWithOther(file):
                if let error = validateDefaultAppSetting(file: file) {
                    state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                    return .none
                }

                return selectApplicationAndOpenFile(for: file, defaultChecked: true, workspaceClient: workspaceClient)

            case let .openFilesWithAppFromOther(files, shouldSetAsDefault):
                for file in files {
                    if let error = validateDefaultAppSetting(file: file) {
                        state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                        return .none
                    }
                }

                return selectApplicationAndOpenFile(
                    for: files,
                    defaultChecked: shouldSetAsDefault,
                    workspaceClient: workspaceClient,
                )

            case let .loadApplicationsForFile(file):
                guard !file.isDirectory else { return .none }
                let filePath = file.fullPath

                guard state.applicationsForItems[filePath] == nil else {
                    return .none
                }

                let url = URL(fileURLWithPath: filePath)
                let fileType = UTType(filenameExtension: file.fileExtension) ?? .data

                return loadApplications(for: filePath, url: url, fileType: fileType)

            case let .applicationsLoaded(filePath, apps):
                state.applicationsForItems[filePath] = apps
                return .none

            case let .loadCommonApplicationsForFiles(files):
                return loadCommonApplications(for: files)

            case let .commonApplicationsLoaded(apps):
                state.commonApplicationsForSelectedFiles = apps
                return .none

            case let .createNewFolder(name, parentPath):
                let parentURL = URL(fileURLWithPath: parentPath)
                let targetPath = parentURL.appendingPathComponent(name).path

                return .run { send in
                    await send(.operationStarted(targetPath, .createFolder))
                    do {
                        try await entryClient.createFolder(parentURL, name)
                        await send(.operationFinished(targetPath, .createFolder, .success(())))
                        let record = EntryActionRecord(
                            actionKind: .createFolder,
                            targets: [.init(beforePath: nil, afterPath: targetPath)],
                        )
                        await send(.entryActionCompleted(record))
                    } catch {
                        await send(.operationFinished(targetPath, .createFolder, .failure(error.fileOpError)))
                    }
                }

            case let .copySelectedItems(files):
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()

                let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
                pasteboard.writeObjects(urls as [NSURL])

                return .none

            case let .pasteItems(sourcePaths, destinationPath, operation, actionKind):
                let destinationURL = URL(fileURLWithPath: destinationPath)
                let destinations = avoidNameCollisions(
                    sourcePaths: sourcePaths,
                    destinationURL: destinationURL,
                    operation: operation,
                )

                guard !destinations.isEmpty else {
                    if operation == .cut {
                        return .run { send in
                            await send(.operationFinished(destinationPath, .pasteFile, .success(())))
                        }
                    }
                    return .none
                }

                let isCopy = operation == .copy

                return .run { [entryClient] send in
                    var targets: [EntryActionRecord.Target] = []

                    for (sourceURL, destURL) in destinations {
                        let sourcePath = sourceURL.path
                        let kind: OperationKind = .pasteFile

                        await send(.operationStarted(sourcePath, kind))

                        do {
                            if isCopy {
                                try await entryClient.pasteFile(sourceURL, destURL)
                            } else {
                                try await entryClient.moveFile(sourceURL, destURL)
                            }
                            targets.append(.init(beforePath: sourcePath, afterPath: destURL.path))
                            await send(.operationFinished(sourcePath, kind, .success(())))
                        } catch let error as FileOpError where error.isFileExists {
                            guard let itemName = error.itemName else {
                                await send(.operationFinished(sourcePath, kind, .failure(error)))
                                continue
                            }

                            let shouldReplace = await MainActor.run {
                                EntryAlertUtils.showReplaceAlert(itemName: itemName, context: .move) == .replace
                            }

                            if shouldReplace {
                                do {
                                    try await entryClient.deleteImmediately(destURL)
                                    if isCopy {
                                        try await entryClient.pasteFile(sourceURL, destURL)
                                    } else {
                                        try await entryClient.moveFile(sourceURL, destURL)
                                    }

                                    let destinationFolder = destURL.deletingLastPathComponent().path
                                    targets.append(.init(beforePath: sourcePath, afterPath: destURL.path))
                                    await send(.operationFinished(destinationFolder, kind, .success(())))
                                } catch {
                                    await send(.operationFinished(sourcePath, kind, .failure(error.fileOpError)))
                                }
                            } else {
                                await send(.operationFinished(sourcePath, kind, .failure(.cancelled)))
                            }
                        } catch {
                            await send(.operationFinished(sourcePath, kind, .failure(error.fileOpError)))
                        }
                    }

                    if !targets.isEmpty {
                        let record = EntryActionRecord(actionKind: actionKind, targets: targets)
                        await send(.entryActionCompleted(record))
                    }
                }

            case let .renameItem(oldPath, newPath):
                let sourceURL = URL(fileURLWithPath: oldPath)
                let destURL = URL(fileURLWithPath: newPath)

                return .run { send in
                    await send(.operationStarted(oldPath, .rename))
                    do {
                        try await entryClient.renameFile(sourceURL, destURL)
                        await send(.operationFinished(oldPath, .rename, .success(())))
                        let record = EntryActionRecord(
                            actionKind: .rename,
                            targets: [.init(beforePath: oldPath, afterPath: newPath)],
                        )
                        await send(.entryActionCompleted(record))
                    } catch let error as FileOpError where error.isFileExists {
                        guard let itemName = error.itemName else {
                            await send(.operationFinished(oldPath, .rename, .failure(error)))
                            return
                        }
                        await MainActor.run {
                            EntryAlertUtils.showRenameConflictAlert(itemName: itemName)
                        }
                        await send(.operationFinished(oldPath, .rename, .failure(error)))
                    } catch {
                        await send(.operationFinished(oldPath, .rename, .failure(error.fileOpError)))
                    }
                }

            case let .moveToTrash(items):
                return runParallelWithTargets(
                    items: items,
                    kind: .moveToTrash,
                    actionKind: .moveToTrash,
                ) { url in
                    let trashURL = try await entryClient.moveToTrashAndReturnURL(url)
                    let result: NSURL? = trashURL as NSURL

                    if let trashURL = result as URL? {
                        let metadata = TrashMetadata(
                            trashPath: trashURL.path,
                            originalPath: url.path,
                            deletedDate: Date(),
                        )
                        await TrashMetadataStore.shared.save(metadata)
                        return EntryActionRecord.Target(
                            beforePath: url.path,
                            afterPath: trashURL.path,
                        )
                    }
                    return nil
                }

            case let .deleteImmediately(items):
                return runParallel(items: items, kind: .deleteImmediately) { url in
                    try await entryClient.deleteImmediately(url)
                }

            case let .emptyTrash(items):
                return runParallel(
                    items: items,
                    kind: .deleteImmediately,
                    operation: { url in
                        try await entryClient.deleteImmediately(url)
                    },
                    onComplete: {
                        await TrashMetadataStore.shared.removeAll()
                    },
                )

            case let .putBackFromTrash(items):
                return .run { [entryClient] send in
                    var targets: [EntryActionRecord.Target] = []

                    for item in items {
                        await send(.operationStarted(item.fullPath, .putBack))

                        guard let metadata = await TrashMetadataStore.shared.find(trashPath: item.fullPath)
                        else {
                            await send(.operationFinished(
                                item.fullPath,
                                .putBack,
                                .failure(.system(message: "Original path not found")),
                            ))
                            continue
                        }

                        let originalPath = metadata.originalPath

                        do {
                            try await entryClient.putBackFromTrash(
                                URL(fileURLWithPath: item.fullPath),
                                originalPath,
                            )
                            await send(.operationFinished(item.fullPath, .putBack, .success(())))
                            targets.append(.init(beforePath: item.fullPath, afterPath: originalPath))
                        } catch let error as FileOpError where error.isFileExists {
                            guard let itemName = error.itemName else {
                                await send(.operationFinished(item.fullPath, .putBack, .failure(error)))
                                continue
                            }

                            let shouldReplace = await MainActor.run {
                                EntryAlertUtils.showReplaceAlert(itemName: itemName, context: .putBack) == .replace
                            }

                            if shouldReplace {
                                do {
                                    let originalURL = URL(fileURLWithPath: originalPath)
                                    try await entryClient.deleteImmediately(originalURL)
                                    try await entryClient.putBackFromTrash(
                                        URL(fileURLWithPath: item.fullPath),
                                        originalPath,
                                    )
                                    await send(.operationFinished(item.fullPath, .putBack, .success(())))
                                    targets.append(.init(beforePath: item.fullPath, afterPath: originalPath))
                                } catch {
                                    await send(.operationFinished(item.fullPath, .putBack, .failure(error.fileOpError)))
                                }
                            } else {
                                await send(.operationFinished(item.fullPath, .putBack, .failure(.cancelled)))
                            }
                        } catch {
                            await send(.operationFinished(item.fullPath, .putBack, .failure(error.fileOpError)))
                        }
                    }

                    if !targets.isEmpty {
                        let record = EntryActionRecord(actionKind: .putBack, targets: targets)
                        await send(.entryActionCompleted(record))
                    }
                }

            case let .compressItems(items):
                let itemURLs = items.map { URL(fileURLWithPath: $0.fullPath) }
                guard let firstItem = items.first else { return .none }
                let parentPath = URL(fileURLWithPath: firstItem.fullPath).deletingLastPathComponent().path

                return .run { [entryClient] send in
                    await send(.operationStarted(parentPath, .compress))

                    do {
                        let archiveURL = try await entryClient.compressItems(itemURLs)
                        await send(.operationFinished(parentPath, .compress, .success(())))
                        entryClient.postFileSystemChanged([archiveURL.path])
                    } catch {
                        await send(.operationFinished(parentPath, .compress, .failure(error.fileOpError)))
                    }
                }

            case let .extractCompressedFile(file):
                let zipURL = URL(fileURLWithPath: file.fullPath)
                let parentPath = zipURL.deletingLastPathComponent().path

                return .run { [entryClient] send in
                    await send(.operationStarted(parentPath, .extract))

                    do {
                        try await entryClient.extractCompressedFile(zipURL)
                        await send(.operationFinished(parentPath, .extract, .success(())))
                        entryClient.postFileSystemChanged([parentPath])
                    } catch {
                        await send(.operationFinished(parentPath, .extract, .failure(error.fileOpError)))
                    }
                }

            case let .setTagsForItems(targets):
                return .run { [entryClient] send in
                    var completedTargets: [EntryActionRecord.Target] = []

                    for target in targets {
                        let filePath = target.file.fullPath
                        let url = URL(fileURLWithPath: filePath)

                        await send(.operationStarted(filePath, .setTags))
                        do {
                            try await entryClient.setTags(url, target.afterTags)
                            await send(.operationFinished(filePath, .setTags, .success(())))
                            completedTargets.append(EntryActionRecord.Target(
                                beforePath: filePath,
                                afterPath: filePath,
                                beforeTags: target.beforeTags,
                                afterTags: target.afterTags,
                            ))
                        } catch {
                            await send(.operationFinished(filePath, .setTags, .failure(error.fileOpError)))
                        }
                    }

                    guard !completedTargets.isEmpty else { return }
                    let record = EntryActionRecord(actionKind: .setTags, targets: completedTargets)
                    await send(.entryActionCompleted(record))
                }
            }
        }
    }

    private func avoidNameCollisions(
        sourcePaths: [String],
        destinationURL: URL,
        operation: ClipboardOperation,
    ) -> [(URL, URL)] {
        var destinations: [(URL, URL)] = []

        for sourcePath in sourcePaths {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let fileName = sourceURL.lastPathComponent
            let sourceParent = sourceURL.deletingLastPathComponent()

            var destURL = destinationURL.appendingPathComponent(fileName)

            if operation == .copy, sourceParent == destinationURL {
                let nameWithoutExtension = fileName.deletingPathExtension()
                let fileExtension = fileName.pathExtension
                var counter = 1

                while entryClient.fileExists(destURL.path) {
                    let name: String = if counter == 1 {
                        fileExtension.isEmpty
                            ? "\(nameWithoutExtension) copy"
                            : "\(nameWithoutExtension) copy.\(fileExtension)"
                    } else {
                        fileExtension.isEmpty
                            ? "\(nameWithoutExtension) copy \(counter)"
                            : "\(nameWithoutExtension) copy \(counter).\(fileExtension)"
                    }
                    destURL = destinationURL.appendingPathComponent(name)
                    counter += 1
                }
            }

            if operation == .cut, sourceParent == destinationURL {
                continue
            }

            destinations.append((sourceURL, destURL))
        }

        return destinations
    }

    private func validateDefaultAppSetting(file: Entry) -> FileOpError? {
        guard !file.isDirectory else {
            return .unsupportedType
        }
        guard capabilities.supportsDefaultAppManagement else {
            return .system(
                message: "Setting default apps is not supported yet.",
                suggestion: "Enable default-app capability before using this action.",
            )
        }
        return nil
    }

    private func run(
        for filePath: String,
        kind: OperationKind,
        operation: @escaping @Sendable () async throws -> Void,
    ) -> Effect<Action> {
        .run { send in
            await send(.operationStarted(filePath, kind))
            do {
                try await operation()
                await send(.operationFinished(filePath, kind, .success(())))
            } catch {
                await send(.operationFinished(filePath, kind, .failure(error.fileOpError)))
            }
        }
    }

    private func runParallel(
        items: [Entry],
        kind: OperationKind,
        operation: @escaping @Sendable (URL) async throws -> Void,
        onComplete: (@Sendable () async -> Void)? = nil,
    ) -> Effect<Action> {
        .run { send in
            await withTaskGroup(of: Void.self) { group in
                for item in items {
                    group.addTask {
                        await send(.operationStarted(item.fullPath, kind))

                        do {
                            let url = URL(fileURLWithPath: item.fullPath)
                            try await operation(url)
                            await send(.operationFinished(item.fullPath, kind, .success(())))
                        } catch {
                            await send(.operationFinished(
                                item.fullPath,
                                kind,
                                .failure(error.fileOpError),
                            ))
                        }
                    }
                }
            }

            await onComplete?()
        }
    }

    private func runParallelWithTargets(
        items: [Entry],
        kind: OperationKind,
        actionKind: EntryActionRecord.ActionKind,
        operation: @escaping @Sendable (URL) async throws -> EntryActionRecord.Target?,
    ) -> Effect<Action> {
        .run { send in
            let accumulator = EntryActionTargetAccumulator()

            await withTaskGroup(of: Void.self) { group in
                for item in items {
                    group.addTask {
                        await send(.operationStarted(item.fullPath, kind))

                        do {
                            let url = URL(fileURLWithPath: item.fullPath)
                            let target = try await operation(url)
                            if let target {
                                await accumulator.append(target)
                            }
                            await send(.operationFinished(item.fullPath, kind, .success(())))
                        } catch {
                            await send(.operationFinished(
                                item.fullPath,
                                kind,
                                .failure(error.fileOpError),
                            ))
                        }
                    }
                }
            }

            let targets = await accumulator.targets
            guard !targets.isEmpty else { return }
            let record = EntryActionRecord(actionKind: actionKind, targets: targets)
            await send(.entryActionCompleted(record))
        }
    }

    private actor EntryActionTargetAccumulator {
        private var storage: [EntryActionRecord.Target] = []

        func append(_ target: EntryActionRecord.Target) {
            storage.append(target)
        }

        var targets: [EntryActionRecord.Target] {
            storage
        }
    }

    private func loadApplications(
        for filePath: String,
        url: URL,
        fileType: UTType,
    ) -> Effect<Action> {
        .run { send in
            let apps = await entryClient.applicationsForFile(url)
            let defaultApp = await entryClient.defaultApplication(fileType)

            let appsWithDefaultFlag = apps.map { app in
                let isDefault = defaultApp?.bundleID == app.bundleID
                return ApplicationInfo(
                    id: app.id,
                    name: app.name,
                    bundleID: app.bundleID,
                    isDefault: isDefault,
                )
            }

            let finalApps = finalizeApplicationList(appsWithDefaultFlag)
            await send(.applicationsLoaded(filePath, finalApps))
        }
    }

    private func loadCommonApplications(for files: [Entry]) -> Effect<Action> {
        .run { [entryClient] send in
            let commonApps = await computeCommonApplications(files: files, entryClient: entryClient)
            let finalApps = finalizeApplicationList(commonApps)
            await send(.commonApplicationsLoaded(finalApps))
        }
    }

    private func computeCommonApplications(
        files: [Entry],
        entryClient: EntryClient,
    ) async -> [ApplicationInfo] {
        let fileInfos = prepareFileInfos(from: files)
        guard !fileInfos.isEmpty else { return [] }

        let allAppMaps = await collectApplicationMaps(fileInfos: fileInfos, entryClient: entryClient)
        guard !allAppMaps.isEmpty else { return [] }

        let commonBundleIDs = findCommonBundleIDs(from: allAppMaps)
        let fileTypeToDefaultApp = await loadDefaultApps(fileInfos: fileInfos, entryClient: entryClient)
        return buildCommonApps(
            bundleIDs: commonBundleIDs,
            appMaps: allAppMaps,
            fileInfos: fileInfos,
            fileTypeToDefaultApp: fileTypeToDefaultApp,
        )
    }

    private struct FileInfo {
        let file: Entry
        let fileType: UTType
        let url: URL
    }

    private func prepareFileInfos(from files: [Entry]) -> [FileInfo] {
        files.compactMap { file in
            guard !file.isDirectory,
                  let fileType = UTType(filenameExtension: file.fileExtension)
            else { return nil }
            return FileInfo(file: file, fileType: fileType, url: URL(fileURLWithPath: file.fullPath))
        }
    }

    private func collectApplicationMaps(
        fileInfos: [FileInfo],
        entryClient: EntryClient,
    ) async -> [[String: ApplicationInfo]] {
        var allAppMaps: [[String: ApplicationInfo]] = []
        await withTaskGroup(of: [String: ApplicationInfo]?.self) { group in
            for fileInfo in fileInfos {
                group.addTask {
                    let apps = await entryClient.applicationsForFile(fileInfo.url)
                    var appMap: [String: ApplicationInfo] = [:]
                    for app in apps {
                        if let bundleID = app.bundleID {
                            appMap[bundleID] = app
                        }
                    }
                    return appMap
                }
            }

            for await appMap in group {
                if let appMap {
                    allAppMaps.append(appMap)
                }
            }
        }
        return allAppMaps
    }

    private func findCommonBundleIDs(from allAppMaps: [[String: ApplicationInfo]]) -> Set<String> {
        guard let firstMap = allAppMaps.first else { return [] }
        var commonBundleIDs = Set(firstMap.keys)
        for appMap in allAppMaps.dropFirst() {
            commonBundleIDs = commonBundleIDs.intersection(Set(appMap.keys))
        }
        return commonBundleIDs
    }

    private func loadDefaultApps(
        fileInfos: [FileInfo],
        entryClient: EntryClient,
    ) async -> [String: String] {
        var fileTypeToDefaultApp: [String: String] = [:]
        await withTaskGroup(of: (String, String?)?.self) { group in
            for fileInfo in fileInfos {
                group.addTask {
                    let defaultApp = await entryClient.defaultApplication(fileInfo.fileType)
                    return (fileInfo.fileType.identifier, defaultApp?.bundleID)
                }
            }

            for await result in group {
                if let (typeID, bundleID) = result, let bundleID {
                    fileTypeToDefaultApp[typeID] = bundleID
                }
            }
        }
        return fileTypeToDefaultApp
    }

    private func buildCommonApps(
        bundleIDs: Set<String>,
        appMaps: [[String: ApplicationInfo]],
        fileInfos: [FileInfo],
        fileTypeToDefaultApp: [String: String],
    ) -> [ApplicationInfo] {
        var commonApps: [ApplicationInfo] = []
        guard let firstAppMap = appMaps.first else { return [] }

        for bundleID in bundleIDs {
            guard let app = firstAppMap[bundleID] else { continue }

            let isDefault = fileInfos.allSatisfy { fileInfo in
                fileTypeToDefaultApp[fileInfo.fileType.identifier] == bundleID
            }

            commonApps.append(ApplicationInfo(
                id: app.id,
                name: app.name,
                bundleID: app.bundleID,
                isDefault: isDefault,
            ))
        }
        return commonApps
    }
}

private nonisolated func finalizeApplicationList(_ apps: [ApplicationInfo]) -> [ApplicationInfo] {
    var result = apps
    result.append(ApplicationInfo(
        id: "other",
        name: "Other…",
        bundleID: nil,
        isDefault: false,
    ))
    result.sort { lhs, rhs in
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault
        }
        return lhs.name < rhs.name
    }
    return result
}

private nonisolated func isInTrash(_ filePath: String, entryClient: EntryClient) -> Bool {
    guard let trashPath = entryClient.trashDirectoryPath(), !trashPath.isEmpty else {
        return false
    }
    return filePath.starts(with: trashPath + "/")
}

private func selectApplicationAndOpenFile(
    for file: Entry,
    defaultChecked: Bool,
    workspaceClient: WorkspaceClient,
) -> Effect<EntriesOperationsFeature.Action> {
    selectApplicationAndOpenFile(for: [file], defaultChecked: defaultChecked, workspaceClient: workspaceClient)
}

private func selectApplicationAndOpenFile(
    for files: [Entry],
    defaultChecked: Bool,
    workspaceClient: WorkspaceClient,
) -> Effect<EntriesOperationsFeature.Action> {
    let fileURLs = files.map { URL(fileURLWithPath: $0.fullPath) }

    return .run { [workspaceClient] send in
        guard let selection = await selectApplication(
            for: fileURLs,
            workspaceClient: workspaceClient,
            defaultChecked: defaultChecked,
        ) else { return }

        for file in files {
            let effects = applyApplicationSelection(selection, to: file)
            for effect in effects {
                await send(effect)
            }
        }
    }
}

private nonisolated func applyApplicationSelection(
    _ selection: ApplicationSelection,
    to file: Entry,
) -> [EntriesOperationsFeature.Action] {
    var effects: [EntriesOperationsFeature.Action] = []

    if selection.setAsDefault, let type = UTType(filenameExtension: file.fileExtension) {
        effects.append(.setDefaultAppForFile(
            type: type,
            bundleID: selection.bundleID,
            file: file,
        ))
    }

    let filePath = file.fullPath
    effects.append(.openFileWithAppBundleID(
        filePath: filePath,
        bundleID: selection.bundleID,
        url: URL(fileURLWithPath: filePath),
    ))

    return effects
}

private class OpenWithPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    let fileURL: URL?
    let fileURLs: [URL]?
    var enableMode: EnableMode
    weak var panel: NSOpenPanel?
    let workspaceClient: WorkspaceClient

    enum EnableMode: Int {
        case recommended = 0
        case all = 1
    }

    init(
        workspaceClient: WorkspaceClient,
        fileURL: URL? = nil,
        fileURLs: [URL]? = nil,
        enableMode: EnableMode = .recommended,
    ) {
        self.fileURL = fileURL
        self.fileURLs = fileURLs
        self.enableMode = enableMode
        self.workspaceClient = workspaceClient
        super.init()
    }

    func panel(_: Any, shouldEnable url: URL) -> Bool {
        guard url.pathExtension == "app" else { return false }
        guard enableMode == .recommended else { return true }

        if let fileURL {
            let supportedApps = workspaceClient.urlsForApplications(fileURL)
            return supportedApps.contains(url)
        } else if let fileURLs {
            for fileURL in fileURLs {
                let supportedApps = workspaceClient.urlsForApplications(fileURL)
                if !supportedApps.contains(url) {
                    return false
                }
            }
            return true
        }
        return false
    }

    @objc
    func enableModeChanged(_ sender: NSPopUpButton) {
        enableMode = EnableMode(rawValue: sender.indexOfSelectedItem) ?? .recommended
        panel?.validateVisibleColumns()
    }
}

private struct ApplicationSelection {
    let bundleID: String
    let type: UTType?
    let setAsDefault: Bool
}

@MainActor
private func createOpenWithAccessoryView(
    delegate: OpenWithPanelDelegate,
    defaultChecked: Bool,
) -> (view: NSView, checkbox: NSButton) {
    let enableLabel = NSTextField(labelWithString: "Enable:")
    enableLabel.isEditable = false
    enableLabel.isBordered = false
    enableLabel.backgroundColor = .clear
    enableLabel.sizeToFit()

    let enablePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26), pullsDown: false)
    enablePopup.addItems(withTitles: ["Recommended Applications", "All Applications"])
    enablePopup.target = delegate
    enablePopup.action = #selector(OpenWithPanelDelegate.enableModeChanged(_:))

    let enableStack = NSStackView(views: [enableLabel, enablePopup])
    enableStack.orientation = .horizontal
    enableStack.spacing = 8
    enableStack.alignment = .centerY

    let checkbox = NSButton(checkboxWithTitle: "Always Open With", target: nil, action: nil)
    checkbox.state = defaultChecked ? .on : .off
    checkbox.sizeToFit()

    let mainStack = NSStackView(views: [enableStack, checkbox])
    mainStack.orientation = .vertical
    mainStack.spacing = 12
    mainStack.alignment = .centerX

    let fittingSize = mainStack.fittingSize
    mainStack.setFrameSize(fittingSize)

    let accessoryView = NSView()
    accessoryView.translatesAutoresizingMaskIntoConstraints = false
    accessoryView.addSubview(mainStack)

    mainStack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        mainStack.centerXAnchor.constraint(equalTo: accessoryView.centerXAnchor),
        mainStack.centerYAnchor.constraint(equalTo: accessoryView.centerYAnchor),
        accessoryView.heightAnchor.constraint(equalToConstant: fittingSize.height + 20),
    ])

    return (accessoryView, checkbox)
}

@MainActor
private func selectApplication(
    for itemURL: URL,
    workspaceClient: WorkspaceClient,
    defaultChecked: Bool = false,
) -> ApplicationSelection? {
    selectApplication(
        fileURL: itemURL,
        fileURLs: nil,
        message: "Choose an application to open the document \"\(itemURL.lastPathComponent)\".",
        defaultChecked: defaultChecked,
        workspaceClient: workspaceClient,
    )
}

@MainActor
private func selectApplication(
    for fileURLs: [URL],
    workspaceClient: WorkspaceClient,
    defaultChecked: Bool = false,
) -> ApplicationSelection? {
    selectApplication(
        fileURL: nil,
        fileURLs: fileURLs,
        message: "Choose an application to open \(fileURLs.count) items.",
        defaultChecked: defaultChecked,
        workspaceClient: workspaceClient,
    )
}

@MainActor
private func selectApplication(
    fileURL: URL?,
    fileURLs: [URL]?,
    message: String,
    defaultChecked: Bool,
    workspaceClient: WorkspaceClient,
) -> ApplicationSelection? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    if #available(macOS 13.0, *) {
        panel.allowedContentTypes = [.application]
    } else {
        panel.allowedFileTypes = ["app"]
    }

    panel.prompt = "Open"
    panel.message = message

    let delegate = OpenWithPanelDelegate(
        workspaceClient: workspaceClient,
        fileURL: fileURL,
        fileURLs: fileURLs,
        enableMode: .recommended,
    )
    panel.delegate = delegate
    delegate.panel = panel

    let (accessoryView, checkbox) = createOpenWithAccessoryView(delegate: delegate, defaultChecked: defaultChecked)
    panel.accessoryView = accessoryView
    panel.isAccessoryViewDisclosed = true

    guard panel.runModal() == .OK, let appURL = panel.url, let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
        return nil
    }

    let type = (fileURL ?? fileURLs?.first).flatMap { UTType(filenameExtension: $0.pathExtension) }
    return ApplicationSelection(
        bundleID: bundleID,
        type: type,
        setAsDefault: checkbox.state == .on,
    )
}

enum OperationKind: Equatable, Hashable, Sendable {
    case openDefault
    case openWithApp(String)
    case setDefaultApp(String)
    case quickLook
    case createFolder
    case pasteFile
    case rename
    case moveToTrash
    case deleteImmediately
    case putBack
    case compress
    case extract
    case setTags
}

extension Error {
    var fileOpError: FileOpError {
        if let error = self as? FileOpError { return error }
        if let nsError = self as NSError?, nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return .notFound
            case NSUserCancelledError:
                return .cancelled
            default:
                return .system(message: nsError.localizedDescription)
            }
        }
        return .system(message: localizedDescription)
    }
}

extension String {
    func deletingPathExtension() -> String {
        (self as NSString).deletingPathExtension
    }

    var pathExtension: String {
        (self as NSString).pathExtension
    }
}

// swiftlint:enable type_body_length file_length
