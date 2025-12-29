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

    var displayName: String {
        switch self {
        case .home:
            FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
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

    var path: String? {
        switch self {
        case .home:
            FileManager.default.homeDirectoryForCurrentUser.path
        case .root:
            "/"
        case .desktop:
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
        case .documents:
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
        case .downloads:
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        case let .custom(path):
            path
        case .other:
            nil
        }
    }

    var icon: Image {
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
            if let path {
                let originalImage = NSWorkspace.shared.icon(forFile: path)
                let resizedImage = resizeImage(originalImage, to: NSSize(width: iconSize, height: iconSize))
                return Image(nsImage: resizedImage)
            } else {
                return Image(systemName: "folder.fill")
            }
        case .root:
            let originalImage = NSWorkspace.shared.icon(forFile: "/")
            let resizedImage = resizeImage(originalImage, to: NSSize(width: iconSize, height: iconSize))
            return Image(nsImage: resizedImage)
        case let .custom(path):
            let originalImage = NSWorkspace.shared.icon(forFile: path)
            let resizedImage = resizeImage(originalImage, to: NSSize(width: iconSize, height: iconSize))
            return Image(nsImage: resizedImage)
        case .other:
            return Image(systemName: "folder.fill")
        }
    }

    static func from(path: String) -> DirectoryOption {
        let fm = FileManager.default
        let homePath = fm.homeDirectoryForCurrentUser.path
        let rootPath = "/"

        if path == homePath {
            return .home
        } else if path == rootPath {
            return .root
        } else if let desktopPath = fm.urls(for: .desktopDirectory, in: .userDomainMask).first?.path,
                  path == desktopPath
        {
            return .desktop
        } else if let documentsPath = fm.urls(for: .documentDirectory, in: .userDomainMask).first?.path,
                  path == documentsPath
        {
            return .documents
        } else if let downloadsPath = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path,
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
        var automaticUpdate: Bool = true
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

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.loadSettings)

            case .loadSettings:
                // 시작 디렉토리 로드
                let startingDir = UserDefaults.standard.string(forKey: SettingsKeys.defaultTabPath)
                    ?? NSHomeDirectory()
                state.startingDirectory = startingDir
                state.selectedDirectoryOption = DirectoryOption.from(path: startingDir)

                // 로그인 시 실행 상태 확인
                let appService = SMAppService.mainApp
                let actualStatus = appService.status
                let isActuallyRegistered = (actualStatus == .enabled)

                let savedValue = UserDefaults.standard.bool(forKey: SettingsKeys.launchAtStartup)
                if savedValue != isActuallyRegistered {
                    state.launchAtStartup = isActuallyRegistered
                    UserDefaults.standard.set(isActuallyRegistered, forKey: SettingsKeys.launchAtStartup)
                } else {
                    state.launchAtStartup = savedValue
                }

                // 자동 업데이트 및 종료 알림 설정
                state.automaticUpdate = UserDefaults.standard
                    .object(forKey: SettingsKeys.automaticUpdate) as? Bool ?? true
                state.alertBeforeQuit = UserDefaults.standard.bool(forKey: SettingsKeys.alertBeforeQuit)

                return .none

            case let .setStartingDirectory(path):
                state.startingDirectory = path
                state.selectedDirectoryOption = DirectoryOption.from(path: path)
                state.startingDirectoryError = nil
                UserDefaults.standard.set(path, forKey: SettingsKeys.defaultTabPath)
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

                if FileManager.default.fileExists(atPath: path) {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
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
                    UserDefaults.standard.set(enabled, forKey: SettingsKeys.launchAtStartup)
                    state.launchAtStartupError = nil
                } catch {
                    state.launchAtStartupError =
                        "Failed to set launch at startup: \(error.localizedDescription)"
                }
                return .none

            case let .toggleAutomaticUpdate(enabled):
                state.automaticUpdate = enabled
                UserDefaults.standard.set(enabled, forKey: SettingsKeys.automaticUpdate)
                state.automaticUpdateError = nil
                AppDelegate.shared?.setAutomaticUpdate(enabled: enabled)
                return .none

            case let .toggleAlertBeforeQuit(enabled):
                state.alertBeforeQuit = enabled
                UserDefaults.standard.set(enabled, forKey: SettingsKeys.alertBeforeQuit)
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
