import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

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
            case let .openFileWithApp(file):
                return selectApplicationAndOpenFile(for: [file], defaultChecked: false)

            case let .openFileWithAppBundleID(filePath, bundleID, url):
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

                    await send(.operationStarted(filePath, .openWithApp(bundleID)))
                    do {
                        try await entryOpenClient.open(url, .bundleID(bundleID))
                        await send(.operationFinished(filePath, .openWithApp(bundleID), .success(())))
                    } catch {
                        await send(.operationFinished(
                            filePath,
                            .openWithApp(bundleID),
                            .failure(error.fileOpError),
                        ))
                    }
                }

            case let .setDefaultAppForFile(type, bundleID, file):
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

            case let .setDefaultAppWithOther(file):
                if let error = EntryOperationsExecutionSupport.validateDefaultAppSetting(file: file) {
                    state.itemStates[file.fullPath] = ItemOperationState(isBusy: false, lastError: error)
                    return .none
                }

                return selectApplicationAndOpenFile(for: [file], defaultChecked: true)

            case let .openFilesWithAppFromOther(files, shouldSetAsDefault):
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

            case let .loadApplicationsForFile(file):
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

            case let .applicationsLoaded(filePath, apps):
                state.applicationsForItems[filePath] = apps
                return .none

            case let .loadCommonApplicationsForFiles(files):
                return EntryOperationsExecutionSupport.loadCommonApplications(
                    for: files,
                    entryOpenClient: entryOpenClient,
                )

            case let .commonApplicationsLoaded(apps):
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
                    actions.append(.setDefaultAppForFile(
                        type: type,
                        bundleID: selection.bundleID,
                        file: file,
                    ))
                }

                let filePath = file.fullPath
                actions.append(.openFileWithAppBundleID(
                    filePath: filePath,
                    bundleID: selection.bundleID,
                    url: URL(fileURLWithPath: filePath),
                ))

                for nextAction in actions {
                    await send(nextAction)
                }
            }
        }
    }
}
