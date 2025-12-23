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
            image.draw(in: NSRect(origin: .zero, size: size),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver,
                       fraction: 1.0)
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

public enum AppTheme: String, CaseIterable, Equatable {
    case light
    case dark
    case system

    var displayName: String {
        switch self {
        case .light:
            "Light"
        case .dark:
            "Dark"
        case .system:
            "Auto"
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .appearance:
            "Appearance"
        }
    }

    var iconName: String {
        switch self {
        case .general:
            "gear"
        case .appearance:
            "paintbrush"
        }
    }
}

@Reducer
struct SettingsFeature {
    static func getDefaultTabPath() -> String {
        UserDefaults.standard.string(forKey: SettingsKeys.defaultTabPath) ?? NSHomeDirectory()
    }

    @ObservableState
    struct State: Equatable {
        var selectedSection: SettingsSection = .general
        var generalSettings = GeneralSettingsState()
        var appearanceSettings = AppearanceSettingsState()
    }

    struct GeneralSettingsState: Equatable {
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

    struct AppearanceSettingsState: Equatable {
        var theme: AppTheme = .system
        var listIconSize: CGFloat = 20
        var gridIconSize: CGFloat = 64
        var listTextSize: CGFloat = 13
        var gridTextSize: CGFloat = 12
    }

    enum Action: Sendable {
        case onAppear
        case loadSettings
        case selectSection(SettingsSection)

        case general(GeneralSettingsAction)
        case appearance(AppearanceSettingsAction)
    }

    enum GeneralSettingsAction: Sendable {
        case setStartingDirectory(String)
        case selectDirectoryOption(DirectoryOption)
        case openOtherDirectoryPanel
        case startingDirectorySelected(String?)
        case toggleLaunchAtStartup(Bool)
        case toggleAutomaticUpdate(Bool)
        case toggleAlertBeforeQuit(Bool)
    }

    enum AppearanceSettingsAction: Sendable {
        case setTheme(AppTheme)
        case setListIconSize(CGFloat)
        case setGridIconSize(CGFloat)
        case setListTextSize(CGFloat)
        case setGridTextSize(CGFloat)
    }

    @Dependency(\.appearanceSettingsClient)
    var appearanceSettingsClient: AppearanceSettingsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.loadSettings)

            case let .selectSection(section):
                state.selectedSection = section
                return .none

            case .loadSettings:
                let startingDir = UserDefaults.standard.string(forKey: SettingsKeys.defaultTabPath)
                    ?? NSHomeDirectory()
                state.generalSettings.startingDirectory = startingDir
                state.generalSettings.selectedDirectoryOption = DirectoryOption.from(path: startingDir)

                let appService = SMAppService.mainApp
                let actualStatus = appService.status
                let isActuallyRegistered = (actualStatus == .enabled)

                let savedValue = UserDefaults.standard.bool(forKey: SettingsKeys.launchAtStartup)
                if savedValue != isActuallyRegistered {
                    state.generalSettings.launchAtStartup = isActuallyRegistered
                    UserDefaults.standard.set(isActuallyRegistered, forKey: SettingsKeys.launchAtStartup)
                } else {
                    state.generalSettings.launchAtStartup = savedValue
                }

                state.generalSettings.automaticUpdate = UserDefaults.standard
                    .object(forKey: SettingsKeys.automaticUpdate) as? Bool ?? true
                state.generalSettings.alertBeforeQuit = UserDefaults.standard.bool(forKey: SettingsKeys.alertBeforeQuit)

                state.appearanceSettings.theme = appearanceSettingsClient.loadTheme()

                let savedListIconSize = UserDefaults.standard.object(forKey: SettingsKeys.listIconSize) as? CGFloat
                if let listIconSize = savedListIconSize {
                    state.appearanceSettings.listIconSize = listIconSize
                }

                let savedGridIconSize = UserDefaults.standard.object(forKey: SettingsKeys.gridIconSize) as? CGFloat
                if let gridIconSize = savedGridIconSize {
                    state.appearanceSettings.gridIconSize = gridIconSize
                }

                let savedListTextSize = UserDefaults.standard.object(forKey: SettingsKeys.listTextSize) as? CGFloat
                if let listTextSize = savedListTextSize {
                    state.appearanceSettings.listTextSize = listTextSize
                }

                let savedGridTextSize = UserDefaults.standard.object(forKey: SettingsKeys.gridTextSize) as? CGFloat
                if let gridTextSize = savedGridTextSize {
                    state.appearanceSettings.gridTextSize = gridTextSize
                }

                return .none

            case let .general(.setStartingDirectory(path)):
                state.generalSettings.startingDirectory = path
                state.generalSettings.selectedDirectoryOption = DirectoryOption.from(path: path)
                state.generalSettings.startingDirectoryError = nil
                UserDefaults.standard.set(path, forKey: SettingsKeys.defaultTabPath)
                return .none

            case let .general(.selectDirectoryOption(option)):
                if case .other = option {
                    return .send(.general(.openOtherDirectoryPanel))
                } else if let path = option.path {
                    return .send(.general(.setStartingDirectory(path)))
                } else {
                    return .none
                }

            case .general(.openOtherDirectoryPanel):
                state.generalSettings.isSelectingDirectory = true
                state.generalSettings.startingDirectoryError = nil
                return .run { send in
                    let path = await Task { @MainActor in
                        showDirectorySelectionPanel()
                    }.value

                    await send(.general(.startingDirectorySelected(path)))
                }

            case let .general(.startingDirectorySelected(path)):
                state.generalSettings.isSelectingDirectory = false
                guard let path else {
                    return .none
                }

                if FileManager.default.fileExists(atPath: path) {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                       isDirectory.boolValue
                    {
                        return .send(.general(.setStartingDirectory(path)))
                    } else {
                        state.generalSettings.startingDirectoryError = "Selected path is not a directory"
                        return .none
                    }
                } else {
                    state.generalSettings.startingDirectoryError = "Invalid directory path"
                    return .none
                }

            case let .general(.toggleLaunchAtStartup(enabled)):
                do {
                    let appService = SMAppService.mainApp
                    if enabled {
                        try appService.register()
                    } else {
                        try appService.unregister()
                    }
                    state.generalSettings.launchAtStartup = enabled
                    UserDefaults.standard.set(enabled, forKey: SettingsKeys.launchAtStartup)
                    state.generalSettings.launchAtStartupError = nil
                } catch {
                    state.generalSettings.launchAtStartupError =
                        "Failed to set launch at startup: \(error.localizedDescription)"
                }
                return .none

            case let .general(.toggleAutomaticUpdate(enabled)):
                state.generalSettings.automaticUpdate = enabled
                UserDefaults.standard.set(enabled, forKey: SettingsKeys.automaticUpdate)
                state.generalSettings.automaticUpdateError = nil
                // TODO: 추후 업데이트 기능 구현 시 여기서 업데이트 체크 로직 연동
                return .none

            case let .general(.toggleAlertBeforeQuit(enabled)):
                state.generalSettings.alertBeforeQuit = enabled
                UserDefaults.standard.set(enabled, forKey: SettingsKeys.alertBeforeQuit)
                return .none

            case let .appearance(.setTheme(theme)):
                state.appearanceSettings.theme = theme
                UserDefaults.standard.set(theme.rawValue, forKey: SettingsKeys.theme)
                return .run { [appearanceSettingsClient] _ in
                    await appearanceSettingsClient.applyTheme(theme)
                }

            case let .appearance(.setListIconSize(size)):
                state.appearanceSettings.listIconSize = size
                UserDefaults.standard.set(size, forKey: SettingsKeys.listIconSize)
                return .none

            case let .appearance(.setGridIconSize(size)):
                state.appearanceSettings.gridIconSize = size
                UserDefaults.standard.set(size, forKey: SettingsKeys.gridIconSize)
                return .none

            case let .appearance(.setListTextSize(size)):
                state.appearanceSettings.listTextSize = size
                UserDefaults.standard.set(size, forKey: SettingsKeys.listTextSize)
                return .none

            case let .appearance(.setGridTextSize(size)):
                state.appearanceSettings.gridTextSize = size
                UserDefaults.standard.set(size, forKey: SettingsKeys.gridTextSize)
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
