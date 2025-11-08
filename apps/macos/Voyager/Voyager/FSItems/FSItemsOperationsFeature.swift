import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

// swiftlint:disable type_body_length file_length
/// FSItems의 파일 시스템 작업 관리
@Reducer
struct FSItemsOperationsFeature {
    @ObservableState
    struct State: Equatable {
        var itemStates: [String: ItemOperationState] = [:]
        var applicationsForItems: [String: [ApplicationInfo]] = [:]
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
        case openFiles(files: [FSItem])
        case quickLookFile(file: FSItem)
        case openFileWithApp(file: FSItem)
        case openFileWithAppBundleID(filePath: String, bundleID: String, url: URL)
        case setDefaultAppForFile(type: UTType?, bundleID: String, file: FSItem)
        case setDefaultAppWithOther(file: FSItem)
        case loadApplicationsForFile(file: FSItem)
        case createNewFolder(name: String, parentPath: String)
        case copySelectedItems(files: [FSItem])
        case pasteItems(sourcePaths: [String], destinationPath: String, operation: ClipboardOperation)
        case renameItem(oldPath: String, newPath: String)
        case moveToTrash(items: [FSItem])
        case deleteImmediately(items: [FSItem])
        case putBackFromTrash(items: [FSItem])
        case emptyTrash(items: [FSItem])
        case compressItems(items: [FSItem])
        case extractCompressedFile(file: FSItem)
        case toggleTagForItem(file: FSItem, tag: String)
        case applicationsLoaded(String, [ApplicationInfo])
        case operationStarted(String, OperationKind)
        case operationFinished(String, OperationKind, Result<Void, FileOpError>)
        case clearError(String)
    }

    @Dependency(\.fileSystemClient)
    var fileSystemClient
    @Dependency(\.fileSystemCapabilities)
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

            case let .openFiles(files):
                guard !files.isEmpty else {
                    return .none
                }

                return .run { send in
                    for file in files {
                        let filePath = file.fullPath
                        let url = URL(fileURLWithPath: filePath)
                        await send(.operationStarted(filePath, .openDefault))
                        do {
                            try await fileSystemClient.open(url, .defaultApp)
                            await send(.operationFinished(filePath, .openDefault, .success(())))
                        } catch {
                            await send(.operationFinished(filePath, .openDefault, .failure(error.fileOpError)))
                        }
                    }
                }

            case let .quickLookFile(file):
                let filePath = file.fullPath
                let url = URL(fileURLWithPath: filePath)
                return run(for: filePath, kind: .quickLook) {
                    try await fileSystemClient.quickLook(url)
                }

            case let .openFileWithApp(file):
                return selectApplicationAndOpenFile(for: file, defaultChecked: false)

            case let .openFileWithAppBundleID(filePath, bundleID, url):
                return run(for: filePath, kind: .openWithApp(bundleID)) {
                    try await fileSystemClient.open(url, .bundleID(bundleID))
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
                    try await fileSystemClient.setDefaultApp(fileType, bundleID)
                }

            case let .setDefaultAppWithOther(file):
                if let error = validateDefaultAppSetting(file: file) {
                    state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                    return .none
                }

                return selectApplicationAndOpenFile(for: file, defaultChecked: true)

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

            case let .createNewFolder(name, parentPath):
                let parentURL = URL(fileURLWithPath: parentPath)
                return run(for: parentPath, kind: .createFolder) {
                    try await fileSystemClient.createFolder(parentURL, name)
                }

            case let .copySelectedItems(files):
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()

                let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
                pasteboard.writeObjects(urls as [NSURL])

                return .none

            case let .pasteItems(sourcePaths, destinationPath, operation):
                let destinationURL = URL(fileURLWithPath: destinationPath)
                let destinations = avoidNameCollisions(
                    sourcePaths: sourcePaths,
                    destinationURL: destinationURL,
                    operation: operation
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

                return .run { [fileSystemClient] send in
                    for (sourceURL, destURL) in destinations {
                        let sourcePath = sourceURL.path
                        let kind: OperationKind = .pasteFile

                        await send(.operationStarted(sourcePath, kind))

                        do {
                            if isCopy {
                                try await fileSystemClient.pasteFile(sourceURL, destURL)
                            } else {
                                try await fileSystemClient.moveFile(sourceURL, destURL)
                            }
                            await send(.operationFinished(sourcePath, kind, .success(())))
                        } catch let error as FileOpError where error.isFileExists {
                            guard let itemName = error.itemName else {
                                await send(.operationFinished(sourcePath, kind, .failure(error)))
                                continue
                            }

                            let shouldReplace = await MainActor.run {
                                FSItemAlertUtils.showReplaceAlert(itemName: itemName, context: .move) == .replace
                            }

                            if shouldReplace {
                                do {
                                    try FileManager.default.removeItem(at: destURL)
                                    if isCopy {
                                        try await fileSystemClient.pasteFile(sourceURL, destURL)
                                    } else {
                                        try await fileSystemClient.moveFile(sourceURL, destURL)
                                    }

                                    let destinationFolder = destURL.deletingLastPathComponent().path
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
                }

            case let .renameItem(oldPath, newPath):
                let sourceURL = URL(fileURLWithPath: oldPath)
                let destURL = URL(fileURLWithPath: newPath)

                return .run { send in
                    await send(.operationStarted(oldPath, .rename))
                    do {
                        try await fileSystemClient.renameFile(sourceURL, destURL)
                        await send(.operationFinished(oldPath, .rename, .success(())))
                    } catch let error as FileOpError where error.isFileExists {
                        guard let itemName = error.itemName else {
                            await send(.operationFinished(oldPath, .rename, .failure(error)))
                            return
                        }
                        await MainActor.run {
                            FSItemAlertUtils.showRenameConflictAlert(itemName: itemName)
                        }
                        await send(.operationFinished(oldPath, .rename, .failure(error)))
                    } catch {
                        await send(.operationFinished(oldPath, .rename, .failure(error.fileOpError)))
                    }
                }

            case let .moveToTrash(items):
                return runParallel(items: items, kind: .moveToTrash) { url in
                    var result: NSURL?
                    try await MainActor.run {
                        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                    }

                    if let trashURL = result as URL? {
                        let metadata = TrashMetadata(
                            trashPath: trashURL.path,
                            originalPath: url.path,
                            deletedDate: Date()
                        )
                        await TrashMetadataStore.shared.save(metadata)
                    }
                }

            case let .deleteImmediately(items):
                return runParallel(items: items, kind: .deleteImmediately) { url in
                    try await fileSystemClient.deleteImmediately(url)
                }

            case let .emptyTrash(items):
                return runParallel(
                    items: items,
                    kind: .deleteImmediately,
                    operation: { url in
                        try await fileSystemClient.deleteImmediately(url)
                    },
                    onComplete: {
                        await TrashMetadataStore.shared.removeAll()
                    }
                )

            case let .putBackFromTrash(items):
                return .run { [fileSystemClient] send in
                    for item in items {
                        await send(.operationStarted(item.fullPath, .putBack))

                        guard let metadata = await TrashMetadataStore.shared.find(trashPath: item.fullPath)
                        else {
                            await send(.operationFinished(
                                item.fullPath,
                                .putBack,
                                .failure(.system(message: "Original path not found"))
                            ))
                            continue
                        }

                        let originalPath = metadata.originalPath

                        do {
                            try await fileSystemClient.putBackFromTrash(
                                URL(fileURLWithPath: item.fullPath),
                                originalPath
                            )
                            await send(.operationFinished(item.fullPath, .putBack, .success(())))
                        } catch let error as FileOpError where error.isFileExists {
                            guard let itemName = error.itemName else {
                                await send(.operationFinished(item.fullPath, .putBack, .failure(error)))
                                continue
                            }

                            let shouldReplace = await MainActor.run {
                                FSItemAlertUtils.showReplaceAlert(itemName: itemName, context: .putBack) == .replace
                            }

                            if shouldReplace {
                                do {
                                    let originalURL = URL(fileURLWithPath: originalPath)
                                    try FileManager.default.removeItem(at: originalURL)
                                    try await fileSystemClient.putBackFromTrash(
                                        URL(fileURLWithPath: item.fullPath),
                                        originalPath
                                    )
                                    await send(.operationFinished(item.fullPath, .putBack, .success(())))
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
                }

            case let .compressItems(items):
                let itemURLs = items.map { URL(fileURLWithPath: $0.fullPath) }
                guard let firstItem = items.first else { return .none }
                let parentPath = URL(fileURLWithPath: firstItem.fullPath).deletingLastPathComponent().path

                return .run { [fileSystemClient] send in
                    await send(.operationStarted(parentPath, .compress))

                    do {
                        let archiveURL = try await fileSystemClient.compressItems(itemURLs)
                        await send(.operationFinished(parentPath, .compress, .success(())))
                        await fileSystemClient.postFileSystemChanged([archiveURL.path])
                    } catch {
                        await send(.operationFinished(parentPath, .compress, .failure(error.fileOpError)))
                    }
                }

            case let .extractCompressedFile(file):
                let zipURL = URL(fileURLWithPath: file.fullPath)
                let parentPath = zipURL.deletingLastPathComponent().path

                return .run { [fileSystemClient] send in
                    await send(.operationStarted(parentPath, .extract))

                    do {
                        try await fileSystemClient.extractCompressedFile(zipURL)
                        await send(.operationFinished(parentPath, .extract, .success(())))
                        fileSystemClient.postFileSystemChanged([parentPath])
                    } catch {
                        await send(.operationFinished(parentPath, .extract, .failure(error.fileOpError)))
                    }
                }

            case let .toggleTagForItem(file, tag):
                let filePath = file.fullPath
                let url = URL(fileURLWithPath: filePath)

                return run(for: filePath, kind: .setTags) {
                    try await fileSystemClient.toggleTag(url, tag)
                }
            }
        }
    }

    private func avoidNameCollisions(
        sourcePaths: [String],
        destinationURL: URL,
        operation: ClipboardOperation
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

                while fileSystemClient.fileExists(destURL.path) {
                    let name: String
                    if counter == 1 {
                        name = fileExtension.isEmpty
                            ? "\(nameWithoutExtension) copy"
                            : "\(nameWithoutExtension) copy.\(fileExtension)"
                    } else {
                        name = fileExtension.isEmpty
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

    private func validateDefaultAppSetting(file: FSItem) -> FileOpError? {
        guard !file.isDirectory else {
            return .unsupportedType
        }
        guard capabilities.supportsDefaultAppManagement else {
            return .system(
                message: "Setting default apps is not supported yet.",
                suggestion: "Enable default-app capability before using this action."
            )
        }
        return nil
    }

    private func run(
        for filePath: String,
        kind: OperationKind,
        operation: @escaping @Sendable () async throws -> Void
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
        items: [FSItem],
        kind: OperationKind,
        operation: @escaping @Sendable (URL) async throws -> Void,
        onComplete: (@Sendable () async -> Void)? = nil
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
                                .failure(error.fileOpError)
                            ))
                        }
                    }
                }
            }

            await onComplete?()
        }
    }

    private func loadApplications(
        for filePath: String,
        url: URL,
        fileType: UTType
    ) -> Effect<Action> {
        .run { send in
            let apps = await fileSystemClient.applicationsForFile(url)
            let defaultApp = await fileSystemClient.defaultApplication(fileType)

            let appsWithDefaultFlag = apps.map { app in
                let isDefault = defaultApp?.bundleID == app.bundleID
                return ApplicationInfo(
                    id: app.id,
                    name: app.name,
                    bundleID: app.bundleID,
                    isDefault: isDefault
                )
            }

            var finalApps = appsWithDefaultFlag
            finalApps.append(ApplicationInfo(
                id: "other",
                name: "Other…",
                bundleID: nil,
                isDefault: false
            ))

            finalApps.sort { lhs, rhs in
                if lhs.isDefault != rhs.isDefault {
                    return lhs.isDefault
                }
                return lhs.name < rhs.name
            }

            await send(.applicationsLoaded(filePath, finalApps))
        }
    }
}

private func selectApplicationAndOpenFile(
    for file: FSItem,
    defaultChecked: Bool
) -> Effect<FSItemsOperationsFeature.Action> {
    let filePath = file.fullPath
    let url = URL(fileURLWithPath: filePath)

    return .run { send in
        guard let selection = await selectApplication(for: url, defaultChecked: defaultChecked) else { return }

        if selection.setAsDefault, let type = selection.type {
            await send(.setDefaultAppForFile(
                type: type,
                bundleID: selection.bundleID,
                file: file
            ))
        }

        await send(.openFileWithAppBundleID(filePath: filePath, bundleID: selection.bundleID, url: url))
    }
}

private struct ApplicationSelection {
    let bundleID: String
    let type: UTType?
    let setAsDefault: Bool
}

@MainActor
private func selectApplication(for itemURL: URL, defaultChecked: Bool = false) -> ApplicationSelection? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    if #available(macOS 13.0, *) {
        panel.allowedContentTypes = [.application]
    } else {
        panel.allowedFileTypes = ["app"]
    }

    panel.prompt = "Open"
    panel.message = "Choose an application to open the document \"\(itemURL.lastPathComponent)\"."

    let checkbox = NSButton(checkboxWithTitle: "Always Open With", target: nil, action: nil)
    checkbox.state = defaultChecked ? .on : .off
    checkbox.sizeToFit()

    let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))

    let xPosition = (accessoryView.frame.width - checkbox.frame.width) / 2
    let yPosition = (accessoryView.frame.height - checkbox.frame.height) / 2
    checkbox.frame = NSRect(x: xPosition, y: yPosition, width: checkbox.frame.width, height: checkbox.frame.height)
    accessoryView.addSubview(checkbox)

    panel.accessoryView = accessoryView
    panel.isAccessoryViewDisclosed = true

    guard panel.runModal() == .OK, let appURL = panel.url, let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
        return nil
    }

    let type = UTType(filenameExtension: itemURL.pathExtension)
    return ApplicationSelection(
        bundleID: bundleID,
        type: type,
        setAsDefault: checkbox.state == .on
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
