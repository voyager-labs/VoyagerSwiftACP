import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

import VoyagerEntitiesEntry
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
                if let error = EntryOperationsExecutionSupport.validateDefaultAppSetting(file: file) {
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
                if let error = EntryOperationsExecutionSupport.validateDefaultAppSetting(file: file) {
                    state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                    return .none
                }

                return selectApplicationAndOpenFile(for: [file], defaultChecked: true)

            case let .openWith(.openFilesWithAppFromOther(files, shouldSetAsDefault)):
                for file in files {
                    if let error = EntryOperationsExecutionSupport.validateDefaultAppSetting(file: file) {
                        state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                        return .none
                    }
                }

                return selectApplicationAndOpenFile(
                    for: files,
                    defaultChecked: shouldSetAsDefault,
                )

            case let .openWith(.loadApplicationsForFile(file)):
                guard !file.isFolder else { return .none }
                let filePath = file.fullPath

                guard state.applicationsForItems[filePath] == nil else {
                    return .none
                }

                let url = URL(fileURLWithPath: filePath)
                let fileType = UTType(filenameExtension: file.fileExtension) ?? .data

                return EntryOperationsExecutionSupport.loadApplications(
                    for: filePath,
                    url: url,
                    fileType: fileType,
                    entryOpenClient: entryOpenClient,
                )

            case let .openWith(.applicationsLoaded(filePath, apps)):
                state.applicationsForItems[filePath] = apps
                return .none

            case let .openWith(.loadCommonApplicationsForFiles(files)):
                return EntryOperationsExecutionSupport.loadCommonApplications(
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
