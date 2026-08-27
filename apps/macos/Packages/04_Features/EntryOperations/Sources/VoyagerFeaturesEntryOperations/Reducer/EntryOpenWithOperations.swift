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
                    var succeededCount = 0
                    var failedCount = 0
                    do {
                        try await entryOpenClient.open(url, .bundleID(bundleID))
                        succeededCount = 1
                        await send(.lifecycle(.operationFinished(filePath, .openWithApp(bundleID), .success(()))))
                    } catch {
                        failedCount = 1
                        await send(.lifecycle(.operationFinished(
                            filePath,
                            .openWithApp(bundleID),
                            .failure(error.fileOpError),
                        )))
                    }
                    // open-with도 실제 OperationKind를 보존한 단일 terminal로 마무리한다.
                    await send(.lifecycle(.entryActionCompleted(
                        EntryActionRecord(
                            operationKind: .openWithApp(bundleID),
                            targets: [],
                            failedCount: failedCount,
                            succeededCount: succeededCount,
                        ),
                    )))
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
                let url = URL(fileURLWithPath: filePath)
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard !isDirectory else { return .none }
                let fileExtension = url.pathExtension
                let fileType = UTType(filenameExtension: fileExtension) ?? .data
                state.applicationsForTypes[fileType.identifier] = nil
                state.openWithCommonRequestGeneration += 1
                state.commonApplicationsForSelectedFiles = []
                state.openWithCommonTypeGenerations[fileType.identifier] = nil
                let generation = state.openWithTypeRequestGenerations[fileType.identifier, default: 0] + 1
                state.openWithTypeRequestGenerations[fileType.identifier] = generation
                state.openWithInFlightTypeIDs.insert(fileType.identifier)

                return .run { [entryOpenClient] send in
                    await entryOpenClient.invalidateApplicationsForType(fileType.identifier)
                    let apps = await entryOpenClient.applicationsForType(fileType, url)
                    let defaultApp = await entryOpenClient.defaultApplication(fileType)

                    let appsWithDefaultFlag = apps.map { app in
                        let isDefault = defaultApp?.bundleID == app.bundleID
                        return ApplicationInfo(
                            id: app.id,
                            name: app.name,
                            bundleID: app.bundleID,
                            isDefault: isDefault,
                            applicationURL: app.applicationURL,
                        )
                    }

                    let finalApps = await MainActor.run {
                        EntryOperationsExecutionSupport.finalizeApplicationList(appsWithDefaultFlag)
                    }
                    await send(.openWith(.applicationsLoaded(
                        typeID: fileType.identifier,
                        generation: generation,
                        finalApps,
                    )))
                }

            case let .openWith(.loadApplicationsForFile(file)):
                guard !file.isFolder else { return .none }
                let filePath = file.fullPath
                let fileType = UTType(filenameExtension: file.fileExtension) ?? .data

                let typeID = fileType.identifier
                guard state.applicationsForTypes[typeID] == nil,
                      state.openWithInFlightTypeIDs.insert(typeID).inserted
                else {
                    return .none
                }
                let generation = state.openWithTypeRequestGenerations[typeID, default: 0] + 1
                state.openWithTypeRequestGenerations[typeID] = generation

                let url = URL(fileURLWithPath: filePath)
                return EntryOpenWithOperationsSupport.loadApplications(
                    for: filePath,
                    url: url,
                    fileType: fileType,
                    generation: generation,
                    entryOpenClient: entryOpenClient,
                )

            case let .openWith(.applicationsLoaded(typeID, generation, apps)):
                guard state.openWithTypeRequestGenerations[typeID] == generation else { return .none }
                state.applicationsForTypes[typeID] = apps
                state.openWithInFlightTypeIDs.remove(typeID)
                return .none

            case let .openWith(.loadCommonApplicationsForFiles(files)):
                state.openWithCommonRequestGeneration += 1
                let generation = state.openWithCommonRequestGeneration
                let typeIDs = Set(files.map {
                    (UTType(filenameExtension: $0.fileExtension) ?? .data).identifier
                })
                state.commonApplicationsForSelectedFiles = []
                for typeID in typeIDs {
                    state.openWithCommonTypeGenerations[typeID] = generation
                    state.openWithInFlightTypeIDs.insert(typeID)
                }
                let unresolvedTypeIDs = typeIDs.subtracting(state.applicationsForTypes.keys)
                guard !typeIDs.isEmpty else { return .none }
                if unresolvedTypeIDs.isEmpty {
                    let appMaps = typeIDs.compactMap { typeID -> [String: ApplicationInfo]? in
                        guard let apps = state.applicationsForTypes[typeID] else { return nil }
                        return Dictionary(uniqueKeysWithValues: apps.compactMap { app in
                            app.bundleID.map { ($0, app) }
                        })
                    }
                    if let firstMap = appMaps.first {
                        let commonIDs = appMaps.dropFirst().reduce(Set(firstMap.keys)) {
                            $0.intersection($1.keys)
                        }
                        let commonApps = EntryOperationsExecutionSupport.finalizeApplicationList(
                            commonIDs.compactMap { firstMap[$0] },
                        )
                        let applicationsByType = Dictionary(uniqueKeysWithValues: typeIDs.compactMap { typeID in
                            state.applicationsForTypes[typeID].map { (typeID, $0) }
                        })
                        state.commonApplicationsForSelectedFiles = commonApps
                        for typeID in applicationsByType.keys {
                            state.openWithCommonTypeGenerations[typeID] = nil
                            state.openWithInFlightTypeIDs.remove(typeID)
                        }
                    }
                    return .none
                }
                return EntryOpenWithOperationsSupport.loadCommonApplications(
                    for: files,
                    generation: generation,
                    entryOpenClient: entryOpenClient,
                )

            case let .openWith(.commonApplicationsLoaded(generation, typeIDs, applicationsByType, apps)):
                guard generation == state.openWithCommonRequestGeneration else {
                    for typeID in typeIDs where state.openWithCommonTypeGenerations[typeID] == generation {
                        state.openWithCommonTypeGenerations[typeID] = nil
                        state.openWithInFlightTypeIDs.remove(typeID)
                    }
                    return .none
                }
                for (typeID, apps) in applicationsByType {
                    state.applicationsForTypes[typeID] = apps
                }
                state.commonApplicationsForSelectedFiles = apps
                for typeID in typeIDs where state.openWithCommonTypeGenerations[typeID] == generation {
                    state.openWithCommonTypeGenerations[typeID] = nil
                    state.openWithInFlightTypeIDs.remove(typeID)
                }
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
            ) else {
                await send(.lifecycle(.entryActionCompleted(EntryActionRecord(
                    operationKind: .openWithApp(""),
                    targets: [],
                    failedCount: 0,
                    cancelledCount: 1,
                    succeededCount: 0,
                    id: UUID(),
                    timestamp: Date(),
                ))))
                return
            }

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
    private struct CommonApplicationsResult {
        let typeIDs: Set<String>
        let applications: [ApplicationInfo]
        let applicationsByType: [String: [ApplicationInfo]]
    }

    static func validateDefaultAppSetting(file: EntryModel) -> FileOpError? {
        guard !file.isFolder else {
            return .unsupportedType
        }
        return nil
    }

    static func loadApplications(
        for _: String,
        url: URL,
        fileType: UTType,
        generation: Int,
        entryOpenClient: EntryOpenClient,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            let apps = await entryOpenClient.applicationsForType(fileType, url)
            let defaultApp = await entryOpenClient.defaultApplication(fileType)

            let appsWithDefaultFlag = apps.map { app in
                let isDefault = defaultApp?.bundleID == app.bundleID
                return ApplicationInfo(
                    id: app.id,
                    name: app.name,
                    bundleID: app.bundleID,
                    isDefault: isDefault,
                    applicationURL: app.applicationURL,
                )
            }

            let finalApps = await MainActor.run {
                EntryOperationsExecutionSupport.finalizeApplicationList(appsWithDefaultFlag)
            }
            await send(.openWith(.applicationsLoaded(
                typeID: fileType.identifier,
                generation: generation,
                finalApps,
            )))
        }
    }

    static func loadCommonApplications(
        for files: [EntryModel],
        generation: Int,
        entryOpenClient: EntryOpenClient,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            let result = await computeCommonApplications(
                files: files,
                entryOpenClient: entryOpenClient,
            )
            let finalApps = await MainActor.run {
                EntryOperationsExecutionSupport.finalizeApplicationList(result.applications)
            }
            await send(.openWith(.commonApplicationsLoaded(
                generation: generation,
                typeIDs: result.typeIDs,
                applicationsByType: result.applicationsByType,
                finalApps,
            )))
        }
    }

    private static func computeCommonApplications(
        files: [EntryModel],
        entryOpenClient: EntryOpenClient,
    ) async -> CommonApplicationsResult {
        let fileInfos = prepareFileInfos(from: files)
        guard !fileInfos.isEmpty else {
            return CommonApplicationsResult(typeIDs: [], applications: [], applicationsByType: [:])
        }

        let representatives = Dictionary(grouping: fileInfos, by: { $0.fileType.identifier }).compactMapValues(\.first)
        let allAppMaps = await collectApplicationMaps(
            fileInfos: Array(representatives.values),
            entryOpenClient: entryOpenClient,
        )
        guard !allAppMaps.isEmpty else {
            return CommonApplicationsResult(
                typeIDs: Set(fileInfos.map(\.fileType.identifier)),
                applications: [],
                applicationsByType: [:],
            )
        }

        let commonBundleIDs = findCommonBundleIDs(from: allAppMaps.map(\.1))
        let fileTypeToDefaultApp = await loadDefaultApps(fileInfos: fileInfos, entryOpenClient: entryOpenClient)
        let appsByType = Dictionary(uniqueKeysWithValues: allAppMaps.map { typeID, appMap in
            (typeID, Array(appMap.values))
        })
        return CommonApplicationsResult(
            typeIDs: Set(fileInfos.map(\.fileType.identifier)),
            applications: buildCommonApps(
                bundleIDs: commonBundleIDs,
                appMaps: allAppMaps.map(\.1),
                fileInfos: fileInfos,
                fileTypeToDefaultApp: fileTypeToDefaultApp,
            ),
            applicationsByType: appsByType,
        )
    }

    private static func prepareFileInfos(from files: [EntryModel]) -> [EntryOperationsExecutionSupport.FileInfo] {
        files.compactMap { file in
            guard !file.isFolder else { return nil }
            let fileType = UTType(filenameExtension: file.fileExtension) ?? .data
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
    ) async -> [(String, [String: ApplicationInfo])] {
        var allAppMaps: [(String, [String: ApplicationInfo])] = []
        let representatives = Dictionary(grouping: fileInfos, by: { $0.fileType.identifier }).compactMapValues(\.first)
        await withTaskGroup(of: (String, [String: ApplicationInfo]).self) { group in
            for fileInfo in representatives.values {
                group.addTask {
                    let apps = await entryOpenClient.applicationsForType(fileInfo.fileType, fileInfo.url)
                    var appMap: [String: ApplicationInfo] = [:]
                    for app in apps {
                        if let bundleID = app.bundleID {
                            appMap[bundleID] = app
                        }
                    }
                    return (fileInfo.fileType.identifier, appMap)
                }
            }

            for await appMap in group {
                allAppMaps.append(appMap)
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
        let uniqueInfos = Dictionary(grouping: fileInfos, by: { $0.fileType.identifier }).compactMapValues(\.first)
        await withTaskGroup(of: (String, String?)?.self) { group in
            for fileInfo in uniqueInfos.values {
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
                applicationURL: app.applicationURL,
            ))
        }
        return commonApps
    }
}
