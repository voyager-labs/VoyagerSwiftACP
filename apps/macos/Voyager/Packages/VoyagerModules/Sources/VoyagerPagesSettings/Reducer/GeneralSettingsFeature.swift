import AppKit
import ComposableArchitecture
import Foundation
import ServiceManagement
import VoyagerShared

@Reducer
struct GeneralSettingsFeature {
    typealias State = GeneralSettingsState
    typealias Action = GeneralSettingsAction

    @Dependency(\.userDefaultsClient)
    var userDefaultsClient: UserDefaultsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadSettings:
                // 시작 디렉토리 로드
                let startingDir = userDefaultsClient.string(SettingsKeys.defaultTabPath)
                    ?? FileManager.default.homeDirectoryForCurrentUser.path
                state.startingDirectory = startingDir
                state.selectedDirectoryOption = DirectoryOption.from(path: startingDir)

                // 로그인 시 실행 상태 확인
                let appService = SMAppService.mainApp
                let actualStatus = appService.status
                let isActuallyRegistered = (actualStatus == .enabled)

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
                return .run { send in
                    let path = await Task { @MainActor in
                        showDirectorySelectionPanel()
                    }.value

                    await send(.startingDirectorySelected(path))
                }

            case let .startingDirectorySelected(path):
                state.isSelectingDirectory = false
                guard let path else {
                    return .none
                }

                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
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
                    let appService = SMAppService.mainApp
                    if enabled {
                        try appService.register()
                    } else {
                        try appService.unregister()
                    }
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
            }
        }
    }
}

@MainActor
private func showDirectorySelectionPanel() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.title = "Select Starting Directory"

    let response = panel.runModal()
    if response == .OK, let url = panel.url {
        return url.path
    } else {
        return nil
    }
}
