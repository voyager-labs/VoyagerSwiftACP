import AppKit
import ComposableArchitecture
import Foundation
import ServiceManagement
import SwiftUI

enum DirectoryOption: Equatable, Hashable, Identifiable {
    case home
    case root
    case desktop
    case documents
    case downloads
    case custom(String)
    case other

    var id: String {
        switch self {
        case .home: "home"
        case .root: "root"
        case .desktop: "desktop"
        case .documents: "documents"
        case .downloads: "downloads"
        case let .custom(path): "custom:\(path)"
        case .other: "other"
        }
    }

    func displayName(entryClient: EntryClient) -> String {
        switch self {
        case .home:
            URL(fileURLWithPath: entryClient.homeDirectory()).lastPathComponent
        case .root:
            "Macintosh HD"
        case .desktop:
            "Desktop"
        case .documents:
            "Documents"
        case .downloads:
            "Downloads"
        case let .custom(path):
            URL(fileURLWithPath: path).lastPathComponent
        case .other:
            "Other..."
        }
    }

    func path(entryClient: EntryClient) -> String? {
        switch self {
        case .home:
            entryClient.homeDirectory()
        case .root:
            "/"
        case .desktop:
            entryClient.urlsForDirectory(.desktopDirectory, .userDomainMask).first?.path
        case .documents:
            entryClient.urlsForDirectory(.documentDirectory, .userDomainMask).first?.path
        case .downloads:
            entryClient.urlsForDirectory(.downloadsDirectory, .userDomainMask).first?.path
        case let .custom(path):
            path
        case .other:
            nil
        }
    }

    func icon(entryClient: EntryClient, workspaceClient: WorkspaceClient) -> Image {
        let iconSize: CGFloat = 14

        func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
            let resizedImage = NSImage(size: size)
            resizedImage.lockFocus()
            image.draw(
                in: NSRect(origin: .zero, size: size),
                from: NSRect(origin: .zero, size: image.size),
                operation: .sourceOver,
                fraction: 1.0,
            )
            resizedImage.unlockFocus()
            return resizedImage
        }

        switch self {
        case .home, .desktop, .documents, .downloads:
            if let path = path(entryClient: entryClient) {
                let originalImage = workspaceClient.iconForFile(path)
                let resizedImage = resizeImage(originalImage, to: NSSize(width: iconSize, height: iconSize))
                return Image(nsImage: resizedImage)
            } else {
                return Image(systemName: "folder.fill")
            }
        case .root:
            let originalImage = workspaceClient.iconForFile("/")
            let resizedImage = resizeImage(originalImage, to: NSSize(width: iconSize, height: iconSize))
            return Image(nsImage: resizedImage)
        case let .custom(path):
            let originalImage = workspaceClient.iconForFile(path)
            let resizedImage = resizeImage(originalImage, to: NSSize(width: iconSize, height: iconSize))
            return Image(nsImage: resizedImage)
        case .other:
            return Image(systemName: "folder.fill")
        }
    }

    static func from(path: String, entryClient: EntryClient) -> DirectoryOption {
        let homePath = entryClient.homeDirectory()
        let rootPath = "/"

        if path == homePath {
            return .home
        } else if path == rootPath {
            return .root
        } else if let desktopPath = entryClient.urlsForDirectory(.desktopDirectory, .userDomainMask).first?.path,
                  path == desktopPath
        {
            return .desktop
        } else if let documentsPath = entryClient.urlsForDirectory(.documentDirectory, .userDomainMask).first?.path,
                  path == documentsPath
        {
            return .documents
        } else if let downloadsPath = entryClient.urlsForDirectory(.downloadsDirectory, .userDomainMask).first?.path,
                  path == downloadsPath
        {
            return .downloads
        } else {
            return .custom(path)
        }
    }

    static var standardOptions: [DirectoryOption] {
        [.home, .root, .desktop, .documents, .downloads]
    }
}

@Reducer
struct GeneralSettingsFeature {
    @ObservableState
    struct State: Equatable {
        var startingDirectory: String = ""
        var selectedDirectoryOption: DirectoryOption = .home
        var isSelectingDirectory: Bool = false
        var startingDirectoryError: String?
        var launchAtStartup: Bool = false
        var launchAtStartupError: String?
        var automaticUpdate: Bool = false
        var automaticUpdateError: String?
        var alertBeforeQuit: Bool = false
    }

    enum Action: Sendable {
        case onAppear
        case loadSettings
        case setStartingDirectory(String)
        case selectDirectoryOption(DirectoryOption)
        case openOtherDirectoryPanel
        case startingDirectorySelected(String?)
        case toggleLaunchAtStartup(Bool)
        case toggleAutomaticUpdate(Bool)
        case toggleAlertBeforeQuit(Bool)
    }

    @Dependency(\.entryClient)
    var entryClient: EntryClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient: UserDefaultsClient
    @Dependency(\.updaterClient)
    var updaterClient: UpdaterClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.loadSettings)

            case .loadSettings:
                // 시작 디렉토리 로드
                let startingDir = userDefaultsClient.string(SettingsKeys.defaultTabPath)
                    ?? entryClient.homeDirectory()
                state.startingDirectory = startingDir
                state.selectedDirectoryOption = DirectoryOption.from(path: startingDir, entryClient: entryClient)

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
                state.selectedDirectoryOption = DirectoryOption.from(path: path, entryClient: entryClient)
                state.startingDirectoryError = nil
                userDefaultsClient.setString(path, SettingsKeys.defaultTabPath)
                return .none

            case let .selectDirectoryOption(option):
                if case .other = option {
                    return .send(.openOtherDirectoryPanel)
                } else if let path = option.path(entryClient: entryClient) {
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

                if entryClient.fileExists(path) {
                    var isDirectory: ObjCBool = false
                    if entryClient.fileExistsAtPath(path, &isDirectory),
                       isDirectory.boolValue
                    {
                        return .send(.setStartingDirectory(path))
                    } else {
                        state.startingDirectoryError = "Selected path is not a directory"
                        return .none
                    }
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
                return .run { _ in
                    await updaterClient.setAutomaticUpdate(enabled)
                }

            case let .toggleAlertBeforeQuit(enabled):
                state.alertBeforeQuit = enabled
                userDefaultsClient.setBool(enabled, SettingsKeys.alertBeforeQuit)
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
