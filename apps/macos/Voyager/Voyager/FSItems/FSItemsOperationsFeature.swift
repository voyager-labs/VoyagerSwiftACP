import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

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
                let filePath = file.fullPath
                let url = URL(fileURLWithPath: filePath)
                return .run { send in
                    if let bundleID = await selectApplication(for: url)?.bundleID {
                        await send(.openFileWithAppBundleID(filePath: filePath, bundleID: bundleID, url: url))
                    }
                }

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

                let filePath = file.fullPath
                let url = URL(fileURLWithPath: filePath)
                return .run { send in
                    if let selection = await selectApplication(for: url) {
                        await send(.setDefaultAppForFile(
                            type: selection.type,
                            bundleID: selection.bundleID,
                            file: file
                        ))
                    }
                }

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

                let paths = files.map { $0.fullPath }
                pasteboard.setString(paths.joined(separator: "\n"), forType: .string)

                return .none

            case let .pasteItems(sourcePaths, destinationPath, operation):
                let destinationURL = URL(fileURLWithPath: destinationPath)
                let destinations = makeUniqueFilePaths(sourcePaths: sourcePaths, destinationURL: destinationURL)

                return run(for: destinationPath, kind: .pasteFile) {
                    for (sourceURL, destURL) in destinations {
                        switch operation {
                        case .copy: try await fileSystemClient.pasteFile(sourceURL, destURL)
                        case .cut: try await fileSystemClient.moveFile(sourceURL, destURL)
                        }
                    }
                }

            case let .renameItem(oldPath, newPath):
                let sourceURL = URL(fileURLWithPath: oldPath)
                let destURL = URL(fileURLWithPath: newPath)

                return run(for: oldPath, kind: .rename) {
                    try await fileSystemClient.renameFile(sourceURL, destURL)
                }

            case let .moveToTrash(items):
                return runBatch(items: items, kind: .moveToTrash) { url in
                    try await fileSystemClient.moveToTrash(url)
                }

            case let .deleteImmediately(items):
                return runBatch(items: items, kind: .deleteImmediately) { url in
                    try await fileSystemClient.deleteImmediately(url)
                }
            }
        }
    }

    private func makeUniqueFilePaths(sourcePaths: [String], destinationURL: URL) -> [(URL, URL)] {
        var destinations: [(URL, URL)] = []

        for sourcePath in sourcePaths {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let fileName = sourceURL.lastPathComponent
            let nameWithoutExtension = fileName.deletingPathExtension()
            let fileExtension = fileName.pathExtension

            var destURL = destinationURL.appendingPathComponent(fileName)
            var counter = 1

            while fileSystemClient.fileExists(destURL.path) {
                if counter == 1 {
                    let name = fileExtension.isEmpty ? "\(nameWithoutExtension) copy" : "\(nameWithoutExtension) copy.\(fileExtension)"
                    destURL = destinationURL.appendingPathComponent(name)
                } else {
                    let name = fileExtension.isEmpty ? "\(nameWithoutExtension) copy \(counter)" : "\(nameWithoutExtension) copy \(counter).\(fileExtension)"
                    destURL = destinationURL.appendingPathComponent(name)
                }
                counter += 1
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

    private func runBatch(
        items: [FSItem],
        kind: OperationKind,
        operation: @escaping @Sendable (URL) async throws -> Void
    ) -> Effect<Action> {
        let paths = items.map { $0.fullPath }

        return .run { send in
            for path in paths {
                await send(.operationStarted(path, kind))
            }

            do {
                for path in paths {
                    let url = URL(fileURLWithPath: path)
                    try await operation(url)
                }

                for path in paths {
                    await send(.operationFinished(path, kind, .success(())))
                }
            } catch {
                for path in paths {
                    await send(.operationFinished(path, kind, .failure(error.fileOpError)))
                }
            }
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

private struct ApplicationSelection {
    let bundleID: String
    let type: UTType?
}

@MainActor
private func selectApplication(for itemURL: URL) -> ApplicationSelection? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    if #available(macOS 13.0, *) {
        panel.allowedContentTypes = [.application]
    } else {
        panel.allowedFileTypes = ["app"]
    }
    panel.prompt = "Choose"
    panel.message = "Select an application for \(itemURL.lastPathComponent)."

    guard panel.runModal() == .OK, let appURL = panel.url, let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
        return nil
    }

    let type = UTType(filenameExtension: itemURL.pathExtension)
    return ApplicationSelection(bundleID: bundleID, type: type)
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
