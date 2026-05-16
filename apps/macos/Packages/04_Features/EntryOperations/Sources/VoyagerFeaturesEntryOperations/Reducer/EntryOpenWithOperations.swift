import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

@Reducer
struct EntryOpenWithOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryOpenClient)
    var entryOpenClient
    @Dependency(\.workspaceClient)
    var workspaceClient
    @Dependency(\.openWithPanelClient)
    var openWithPanelClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .openWith(.openFileWithApp(file)):
                return selectApplicationAndOpenFile(for: [file], defaultChecked: false)

            case let .openWith(.openFileWithAppBundleID(filePath, bundleID, url)):
                return .run { [entryOpenClient, alertClient] send in
                    let isTrash = await MainActor.run {
                        guard let trashPath = entryOpenClient.trashDirectoryPath(), !trashPath.isEmpty else {
                            return false
                        }
                        return filePath.starts(with: trashPath + "/")
                    }
                    if isTrash {
                        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                        _ = await alertClient.showTrashFileAlert(fileName, false)
                        return
                    }

                    await send(.lifecycle(.operationStarted(filePath, .openWithApp(bundleID))))
                    do {
                        try await entryOpenClient.open(url, .bundleID(bundleID))
                        await send(.lifecycle(.operationFinished(filePath, .openWithApp(bundleID), .success(()))))
                    } catch {
                        await send(.lifecycle(.operationFinished(
                            filePath,
                            .openWithApp(bundleID),
                            .failure(error.fileOpError),
                        )))
                    }
                }

            case let .openWith(.setDefaultAppForFile(type, bundleID, file)):
                if let error = EntryOpenWithOperationsSupport.validateDefaultAppSetting(file: file) {
                    state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                    return .none
                }

                let resolvedType = type ?? UTType(filenameExtension: file.fileExtension)
                guard let fileType = resolvedType else {
                    state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: .unsupportedType)
                    return .none
                }

                let filePath = file.fullPath
                return EntryOperationsExecutionSupport.run(for: filePath, kind: .setDefaultApp(bundleID)) {
                    try await entryOpenClient.setDefaultApp(fileType, bundleID)
                }

            case let .openWith(.setDefaultAppWithOther(file)):
                if let error = EntryOpenWithOperationsSupport.validateDefaultAppSetting(file: file) {
                    state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                    return .none
                }

                return selectApplicationAndOpenFile(for: [file], defaultChecked: true)

            case let .openWith(.openFilesWithAppFromOther(files, shouldSetAsDefault)):
                for file in files {
                    if let error = EntryOpenWithOperationsSupport.validateDefaultAppSetting(file: file) {
                        state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                        return .none
                    }
                }

                return selectApplicationAndOpenFile(
                    for: files,
                    defaultChecked: shouldSetAsDefault,
                )

            case let .lifecycle(.operationFinished(filePath, .setDefaultApp, .success)):
                state.applicationsForItems[filePath] = nil
                let url = URL(fileURLWithPath: filePath)
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard !isDirectory else { return .none }
                let fileExtension = url.pathExtension
                let fileType = UTType(filenameExtension: fileExtension) ?? .data

                return .run { [entryOpenClient] send in
                    let apps = await entryOpenClient.applicationsForFile(url)
                    let defaultApp = await entryOpenClient.defaultApplication(fileType)

                    let appsWithDefaultFlag = apps.map { app in
                        let isDefault = defaultApp?.bundleID == app.bundleID
                        return ApplicationInfo(
                            id: app.id,
                            name: app.name,
                            bundleID: app.bundleID,
                            isDefault: isDefault,
                        )
                    }

                    let finalApps = await MainActor.run {
                        EntryOperationsExecutionSupport.finalizeApplicationList(appsWithDefaultFlag)
                    }
                    await send(.openWith(.applicationsLoaded(filePath, finalApps)))
                }

            case let .openWith(.loadApplicationsForFile(file)):
                guard !file.isFolder else { return .none }
                let filePath = file.fullPath

                guard state.applicationsForItems[filePath] == nil else {
                    return .none
                }

                let url = URL(fileURLWithPath: filePath)
                let fileType = UTType(filenameExtension: file.fileExtension) ?? .data

                return EntryOpenWithOperationsSupport.loadApplications(
                    for: filePath,
                    url: url,
                    fileType: fileType,
                    entryOpenClient: entryOpenClient,
                )

            case let .openWith(.applicationsLoaded(filePath, apps)):
                state.applicationsForItems[filePath] = apps
                return .none

            case let .openWith(.loadCommonApplicationsForFiles(files)):
                return EntryOpenWithOperationsSupport.loadCommonApplications(
                    for: files,
                    entryOpenClient: entryOpenClient,
                )

            case let .openWith(.commonApplicationsLoaded(apps)):
                state.commonApplicationsForSelectedFiles = apps
                return .none

            default:
                return .none
            }
        }
    }

    private func selectApplicationAndOpenFile(
        for files: [EntryModel],
        defaultChecked: Bool,
    ) -> Effect<Action> {
        let fileURLs = files.map { URL(fileURLWithPath: $0.fullPath) }

        return .run { [workspaceClient, openWithPanelClient] send in
            guard let selection = await openWithPanelClient.selectApplication(
                fileURLs,
                defaultChecked,
                workspaceClient,
            ) else { return }

            for file in files {
                var actions: [Action] = []

                if selection.setAsDefault, let type = UTType(filenameExtension: file.fileExtension) {
                    actions.append(.openWith(.setDefaultAppForFile(
                        type: type,
                        bundleID: selection.bundleID,
                        file: file,
                    )))
                }

                let filePath = file.fullPath
                actions.append(.openWith(.openFileWithAppBundleID(
                    filePath: filePath,
                    bundleID: selection.bundleID,
                    url: URL(fileURLWithPath: filePath),
                )))

                for nextAction in actions {
                    await send(nextAction)
                }
            }
        }
    }
}

private enum EntryOpenWithOperationsSupport {
    static func validateDefaultAppSetting(file: EntryModel) -> FileOpError? {
        guard !file.isFolder else {
            return .unsupportedType
        }
        return nil
    }

    static func loadApplications(
        for filePath: String,
        url: URL,
        fileType: UTType,
        entryOpenClient: EntryOpenClient,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            let apps = await entryOpenClient.applicationsForFile(url)
            let defaultApp = await entryOpenClient.defaultApplication(fileType)

            let appsWithDefaultFlag = apps.map { app in
                let isDefault = defaultApp?.bundleID == app.bundleID
                return ApplicationInfo(
                    id: app.id,
                    name: app.name,
                    bundleID: app.bundleID,
                    isDefault: isDefault,
                )
            }

            let finalApps = await MainActor.run {
                EntryOperationsExecutionSupport.finalizeApplicationList(appsWithDefaultFlag)
            }
            await send(.openWith(.applicationsLoaded(filePath, finalApps)))
        }
    }

    static func loadCommonApplications(
        for files: [EntryModel],
        entryOpenClient: EntryOpenClient,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            let commonApps = await computeCommonApplications(files: files, entryOpenClient: entryOpenClient)
            let finalApps = await MainActor.run {
                EntryOperationsExecutionSupport.finalizeApplicationList(commonApps)
            }
            await send(.openWith(.commonApplicationsLoaded(finalApps)))
        }
    }

    private static func computeCommonApplications(
        files: [EntryModel],
        entryOpenClient: EntryOpenClient,
    ) async -> [ApplicationInfo] {
        let fileInfos = prepareFileInfos(from: files)
        guard !fileInfos.isEmpty else { return [] }

        let allAppMaps = await collectApplicationMaps(fileInfos: fileInfos, entryOpenClient: entryOpenClient)
        guard !allAppMaps.isEmpty else { return [] }

        let commonBundleIDs = findCommonBundleIDs(from: allAppMaps)
        let fileTypeToDefaultApp = await loadDefaultApps(fileInfos: fileInfos, entryOpenClient: entryOpenClient)
        return buildCommonApps(
            bundleIDs: commonBundleIDs,
            appMaps: allAppMaps,
            fileInfos: fileInfos,
            fileTypeToDefaultApp: fileTypeToDefaultApp,
        )
    }

    private static func prepareFileInfos(from files: [EntryModel]) -> [EntryOperationsExecutionSupport.FileInfo] {
        files.compactMap { file in
            guard !file.isFolder,
                  let fileType = UTType(filenameExtension: file.fileExtension)
            else { return nil }
            return EntryOperationsExecutionSupport.FileInfo(
                file: file,
                fileType: fileType,
                url: URL(fileURLWithPath: file.fullPath),
            )
        }
    }

    private static func collectApplicationMaps(
        fileInfos: [EntryOperationsExecutionSupport.FileInfo],
        entryOpenClient: EntryOpenClient,
    ) async -> [[String: ApplicationInfo]] {
        var allAppMaps: [[String: ApplicationInfo]] = []
        await withTaskGroup(of: [String: ApplicationInfo]?.self) { group in
            for fileInfo in fileInfos {
                group.addTask {
                    let apps = await entryOpenClient.applicationsForFile(fileInfo.url)
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

    private static func findCommonBundleIDs(from allAppMaps: [[String: ApplicationInfo]]) -> Set<String> {
        guard let firstMap = allAppMaps.first else { return [] }
        var commonBundleIDs = Set(firstMap.keys)
        for appMap in allAppMaps.dropFirst() {
            commonBundleIDs = commonBundleIDs.intersection(Set(appMap.keys))
        }
        return commonBundleIDs
    }

    private static func loadDefaultApps(
        fileInfos: [EntryOperationsExecutionSupport.FileInfo],
        entryOpenClient: EntryOpenClient,
    ) async -> [String: String] {
        var fileTypeToDefaultApp: [String: String] = [:]
        await withTaskGroup(of: (String, String?)?.self) { group in
            for fileInfo in fileInfos {
                group.addTask {
                    let defaultApp = await entryOpenClient.defaultApplication(fileInfo.fileType)
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

    private static func buildCommonApps(
        bundleIDs: Set<String>,
        appMaps: [[String: ApplicationInfo]],
        fileInfos: [EntryOperationsExecutionSupport.FileInfo],
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
