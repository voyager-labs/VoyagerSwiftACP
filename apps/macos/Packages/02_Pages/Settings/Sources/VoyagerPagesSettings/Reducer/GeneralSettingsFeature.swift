import ComposableArchitecture
import VoyagerEntitiesAppPreferences
import VoyagerShared

@Reducer
struct GeneralSettingsFeature {
    typealias State = GeneralSettingsState
    typealias Action = GeneralSettingsAction

    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.launchAtLoginClient)
    var launchAtLoginClient
    @Dependency(\.directorySelectionClient)
    var directorySelectionClient
    @Dependency(\.defaultFileViewerClient)
    var defaultFileViewerClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadSettings:
                // 시작 디렉토리 로드
                let startingDir = userDefaultsClient.string(SettingsKeys.defaultTabPath)
                    ?? directorySelectionClient.defaultHomePath()
                state.startingDirectory = startingDir
                state.selectedDirectoryOption = DirectoryOption.from(path: startingDir)

                // 로그인 시 실행 상태 확인
                let isActuallyRegistered = launchAtLoginClient.isEnabled()

                let savedValue = userDefaultsClient.bool(SettingsKeys.launchAtStartup)
                if savedValue != isActuallyRegistered {
                    state.launchAtStartup = isActuallyRegistered
                    userDefaultsClient.setBool(isActuallyRegistered, SettingsKeys.launchAtStartup)
                } else {
                    state.launchAtStartup = savedValue
                }

                // 자동 업데이트 및 종료 알림 설정
                state.automaticUpdate = userDefaultsClient
                    .object(SettingsKeys.automaticUpdate) as? Bool ?? false
                state.alertBeforeQuit = userDefaultsClient.bool(SettingsKeys.alertBeforeQuit)

                return .none

            case let .setStartingDirectory(path):
                state.startingDirectory = path
                state.selectedDirectoryOption = DirectoryOption.from(path: path)
                state.startingDirectoryError = nil
                userDefaultsClient.setString(path, SettingsKeys.defaultTabPath)
                return .none

            case let .selectDirectoryOption(option):
                if case .other = option {
                    return .send(.openOtherDirectoryPanel)
                } else if let path = option.path {
                    return .send(.setStartingDirectory(path))
                } else {
                    return .none
                }

            case .openOtherDirectoryPanel:
                state.isSelectingDirectory = true
                state.startingDirectoryError = nil
                return .run { [directorySelectionClient] send in
                    let path = await directorySelectionClient.pickDirectory()
                    await send(.startingDirectorySelected(path))
                }

            case let .startingDirectorySelected(path):
                state.isSelectingDirectory = false
                guard let path else {
                    return .none
                }

                if directorySelectionClient.pathExists(path) {
                    if directorySelectionClient.isDirectory(path) {
                        return .send(.setStartingDirectory(path))
                    }
                    state.startingDirectoryError = "Selected path is not a directory"
                    return .none
                } else {
                    state.startingDirectoryError = "Invalid directory path"
                    return .none
                }

            case let .toggleLaunchAtStartup(enabled):
                do {
                    try launchAtLoginClient.setEnabled(enabled)
                    state.launchAtStartup = enabled
                    userDefaultsClient.setBool(enabled, SettingsKeys.launchAtStartup)
                    state.launchAtStartupError = nil
                } catch {
                    state.launchAtStartupError =
                        "Failed to set launch at startup: \(error.localizedDescription)"
                }
                return .none

            case let .toggleAutomaticUpdate(enabled):
                state.automaticUpdate = enabled
                userDefaultsClient.setBool(enabled, SettingsKeys.automaticUpdate)
                state.automaticUpdateError = nil
                return .none

            case let .toggleAlertBeforeQuit(enabled):
                state.alertBeforeQuit = enabled
                userDefaultsClient.setBool(enabled, SettingsKeys.alertBeforeQuit)
                return .none

            case .checkForUpdates:
                return .none

            case .defaultFileViewerSectionAppeared, .defaultFileViewerDiagnoseRequested:
                state.isDiagnosingDefaultFileViewer = true
                return .run { [defaultFileViewerClient] send in
                    let status = await defaultFileViewerClient.diagnose()
                    await send(.defaultFileViewerDiagnosisCompleted(status))
                }

            case let .defaultFileViewerDiagnosisCompleted(status):
                state.isDiagnosingDefaultFileViewer = false
                state.defaultFileViewerStatus = status
                return .none

            case .setAsDefaultFileViewerTapped:
                guard !state.isSettingDefaultFileViewer else { return .none }
                state.isSettingDefaultFileViewer = true
                state.defaultFileViewerErrorMessage = nil
                return .run { [defaultFileViewerClient] send in
                    do {
                        try await defaultFileViewerClient.setVoyagerAsDefault()
                        await send(.setAsDefaultFileViewerSucceeded)
                    } catch {
                        await send(.setAsDefaultFileViewerFailed(
                            error as? DefaultFileViewerError ?? .systemError("\(error)"),
                        ))
                    }
                }

            case .setAsDefaultFileViewerSucceeded:
                state.isSettingDefaultFileViewer = false
                state.isDiagnosingDefaultFileViewer = true
                return .run { [defaultFileViewerClient] send in
                    let status = await defaultFileViewerClient.diagnose()
                    await send(.defaultFileViewerDiagnosisCompleted(status))
                }

            case let .setAsDefaultFileViewerFailed(error):
                state.isSettingDefaultFileViewer = false
                state.defaultFileViewerErrorMessage = errorMessage(for: error)
                return .none

            case .restoreDefaultFileViewerTapped:
                guard !state.isRestoringDefaultFileViewer else { return .none }
                state.isRestoringDefaultFileViewer = true
                state.defaultFileViewerErrorMessage = nil
                return .run { [defaultFileViewerClient] send in
                    do {
                        try await defaultFileViewerClient.restoreFinder()
                        await send(.restoreDefaultFileViewerSucceeded)
                    } catch {
                        await send(.restoreDefaultFileViewerFailed(
                            error as? DefaultFileViewerError ?? .systemError("\(error)"),
                        ))
                    }
                }

            case .restoreDefaultFileViewerSucceeded:
                state.isRestoringDefaultFileViewer = false
                state.isDiagnosingDefaultFileViewer = true
                return .run { [defaultFileViewerClient] send in
                    let status = await defaultFileViewerClient.diagnose()
                    await send(.defaultFileViewerDiagnosisCompleted(status))
                }

            case let .restoreDefaultFileViewerFailed(error):
                state.isRestoringDefaultFileViewer = false
                state.defaultFileViewerErrorMessage = errorMessage(for: error)
                return .none
            }
        }
    }
}

private func errorMessage(for error: DefaultFileViewerError) -> String {
    switch error {
    case .permissionDenied:
        "시스템 설정 변경 권한이 없습니다"
    case let .systemError(msg):
        "시스템 오류: \(msg)"
    case let .partialWrite(message):
        "부분적으로 설정되었습니다: \(message)"
    }
}
