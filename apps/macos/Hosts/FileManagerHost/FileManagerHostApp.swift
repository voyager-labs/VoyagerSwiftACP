import AppKit
import Combine
import ComposableArchitecture
import SwiftUI
import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

private enum FileManagerHostOneDriveIcon {
    /// 고정 원본: https://github.com/microsoft/agent-academy/blob/7be759608d485979f4b9f5f34468f80f844fca66/docs/public/product-icons/onedrive.svg
    nonisolated static func load() -> NSImage? {
        guard let image = NSImage(named: NSImage.Name("FileManagerHostOneDrive")),
              image.size.width > 0,
              image.size.height > 0
        else { return nil }

        image.isTemplate = false
        return image
    }
}

@MainActor
private enum FileManagerHostSmokeMode {
    static var isEnabled: Bool {
        // Smoke/Reset/Scenario는 호스트 전용 디버그 launch 환경변수이다.
        // Dotenv로 전환하지 않고 ProcessInfo를 직접 읽는다 — 이는 호스트 제어이므로
        // 런타임 설정(.env)과 분리된 상태를 유지한다.
        ProcessInfo.processInfo.environment["FILE_MANAGER_HOST_SMOKE"] == "1"
    }

    static func runIfNeeded() {
        guard isEnabled else { return }

        _ = NSApplication.shared
        let windowController = FileManagerHostFixture.makeWindowController(
            oneDriveIcon: FileManagerHostOneDriveIcon.load,
        )
        windowController.showWindow(nil)
        _ = windowController.window?.contentViewController?.view
        exit(0)
    }
}

@main
struct FileManagerHostApp: App {
    @NSApplicationDelegateAdaptor(FileManagerHostAppDelegate.self)
    private var appDelegate

    init() {
        // EnvironmentLoader는 shared Dotenv를 통해 런타임 설정을 .env.dev에서 로드한다.
        // smoke/reset/scenario는 의도적으로 ProcessInfo launch 환경변수로 남겨두며,
        // 이는 호스트 전용 디버그 제어이므로 Dotenv로 전환하지 않는다.
        try? EnvironmentLoader.loadEnvFiles()
        EnvironmentLoader.requireAppEnv()

        FileManagerHostSmokeMode.runIfNeeded()
    }

    var body: some Scene {
        Settings {
            ZStack {
                FileManagerHostScenarioPicker(
                    initialPreset: appDelegate.initialPreset,
                    onSelect: { appDelegate.selectPreset($0) },
                )
            }
        }
    }
}

@MainActor
private final class FileManagerHostAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var initialPreset = FileManagerHostPreset.resolveFromEnvironment()
    private var windowControllers: [FileManagerWindowCoordinator] = []
    private var menuController: FileManagerHostMenuController?
    private let materialTuning = FileManagerHostMaterialTuningState()
    private var materialTuningPanel: NSPanel?

    override init() {
        super.init()
        materialTuning.onUpdate = { [weak self] configuration in
            self?.windowControllers.forEach {
                FileManagerHostFixture.updateMaterialConfiguration(configuration, in: $0)
            }
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        let preset = initialPreset
        DispatchQueue.main.async { [weak self] in
            self?.showWindow(for: preset)
        }
    }

    func applicationDidBecomeActive(_: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.menuController?.install()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func selectPreset(_ preset: FileManagerHostPreset) {
        let controllers = windowControllers
        windowControllers.removeAll()
        controllers.forEach { $0.close() }
        initialPreset = preset
        showWindow(for: preset)
    }

    private func showWindow(for preset: FileManagerHostPreset) {
        let controller = FileManagerHostFixture.makeWindowController(
            preset: preset,
            oneDriveIcon: FileManagerHostOneDriveIcon.load,
            onBecameKey: { [weak self] windowID in
                self?.activateWindow(windowID)
            },
            onWillClose: { [weak self] windowID in
                self?.removeWindow(windowID)
            },
            materialConfiguration: materialTuning.configuration,
        )
        windowControllers.append(controller)
        if let menuController {
            menuController.updateStore(controller.store)
        } else {
            menuController = FileManagerHostMenuController(
                store: controller.store,
                onNewWindow: { [weak self] in
                    guard let self else { return }
                    showWindow(for: initialPreset)
                },
                onMaterialTuning: { [weak self] in
                    self?.showMaterialTuningPanel()
                },
            )
            menuController?.install()
        }
        controller.showWindow(nil)
        presentWindow(controller)
        DispatchQueue.main.async { [weak self, weak controller] in
            guard let self,
                  let controller,
                  windowControllers.contains(where: { $0 === controller })
            else { return }
            presentWindow(controller)
        }
    }

    private func activateWindow(_ windowID: UUID) {
        guard let controller = windowControllers.first(where: { $0.windowID == windowID }) else { return }
        menuController?.updateStore(controller.store)
        menuController?.install()
    }

    private func removeWindow(_ windowID: UUID) {
        windowControllers.removeAll { $0.windowID == windowID }
    }

    private func presentWindow(_ controller: FileManagerWindowCoordinator) {
        guard let window = controller.window else { return }
        if window.frame.width < 2 || window.frame.height < 2 {
            let visibleFrame = NSScreen.main?.visibleFrame
                ?? NSRect(x: 100, y: 100, width: 1440, height: 900)
            let size = NSSize(width: 960, height: 510)
            window.setFrame(
                NSRect(
                    x: visibleFrame.midX - size.width / 2,
                    y: visibleFrame.midY - size.height / 2,
                    width: size.width,
                    height: size.height,
                ),
                display: true,
                animate: false,
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func showMaterialTuningPanel() {
        if let materialTuningPanel {
            materialTuningPanel.center()
            materialTuningPanel.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: FileManagerHostMaterialTuningPanel(tuningState: materialTuning),
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 510),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false,
        )
        panel.title = "Material Tuning"
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        materialTuningPanel = panel
    }
}

@MainActor
private final class FileManagerHostMenuController: NSObject, NSMenuItemValidation {
    private var store: StoreOf<FileManagerFeature>
    private let onNewWindow: () -> Void
    private let onMaterialTuning: () -> Void
    private var hostMenuItem: NSMenuItem?

    init(
        store: StoreOf<FileManagerFeature>,
        onNewWindow: @escaping () -> Void,
        onMaterialTuning: @escaping () -> Void,
    ) {
        self.store = store
        self.onNewWindow = onNewWindow
        self.onMaterialTuning = onMaterialTuning
    }

    func updateStore(_ store: StoreOf<FileManagerFeature>) {
        self.store = store
    }

    func install() {
        let mainMenu = NSApp.mainMenu ?? NSMenu(title: "Main Menu")
        if NSApp.mainMenu == nil {
            NSApp.mainMenu = mainMenu
        }

        if let existingHostMenuItem = mainMenu.items.first(where: { $0.title == "Host" }) {
            mainMenu.removeItem(existingHostMenuItem)
        }

        let hostMenu = NSMenu(title: "Host")
        let hostMenuItem = NSMenuItem(title: "Host", action: nil, keyEquivalent: "")
        hostMenuItem.submenu = hostMenu
        mainMenu.addItem(hostMenuItem)
        self.hostMenuItem = hostMenuItem

        installNewWindowItem(in: hostMenu)
        hostMenu.addItem(
            withTitle: "Material Tuning…",
            action: #selector(showMaterialTuning),
            keyEquivalent: "",
        ).target = self

        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(
            withTitle: "Icon View",
            action: #selector(selectIconView),
            keyEquivalent: "",
        ).target = self
        viewMenu.addItem(
            withTitle: "List View",
            action: #selector(selectListView),
            keyEquivalent: "",
        ).target = self
        hostMenu.setSubmenu(viewMenu, for: hostMenu.addItem(withTitle: "View", action: nil, keyEquivalent: ""))

        let paneMenu = NSMenu(title: "Panes")
        paneMenu.addItem(
            withTitle: "Show Chat History",
            action: #selector(showChatHistory),
            keyEquivalent: "",
        ).target = self
        paneMenu.addItem(
            withTitle: "Hide Sidebar",
            action: #selector(hideSidebar),
            keyEquivalent: "",
        ).target = self
        paneMenu.addItem(
            withTitle: "Show Sidebar",
            action: #selector(showSidebar),
            keyEquivalent: "",
        ).target = self
        paneMenu.addItem(
            withTitle: "Toggle Sidebar",
            action: #selector(toggleSidebar),
            keyEquivalent: "",
        ).target = self
        hostMenu.setSubmenu(paneMenu, for: hostMenu.addItem(withTitle: "Panes", action: nil, keyEquivalent: ""))
    }

    private func installNewWindowItem(in hostMenu: NSMenu) {
        hostMenu.addItem(
            withTitle: "New Window",
            action: #selector(newWindow),
            keyEquivalent: "n",
        ).target = self
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let projection = store.withState { $0.menuCommandProjection }

        switch menuItem.title {
        case "New Window":
            return true
        case "Icon View":
            menuItem.state = projection.viewLayout == .grid ? .on : .off
            return true
        case "List View":
            menuItem.state = projection.viewLayout == .list ? .on : .off
            return true
        case "Show Chat History":
            menuItem.state = projection.isContextualAiChatPresented ? .on : .off
            return true
        case "Hide Sidebar":
            return projection.sidebarVisible
        case "Show Sidebar":
            return !projection.sidebarVisible
        case "Toggle Sidebar":
            return true
        default:
            return true
        }
    }

    @objc
    private func newWindow(_: NSMenuItem) {
        onNewWindow()
    }

    @objc
    private func showMaterialTuning(_: NSMenuItem) {
        onMaterialTuning()
    }

    @objc
    private func selectIconView(_: NSMenuItem) {
        store.send(.request(.setViewLayout(.grid)))
    }

    @objc
    private func selectListView(_: NSMenuItem) {
        store.send(.request(.setViewLayout(.list)))
    }

    @objc
    private func showChatHistory(_: NSMenuItem) {
        store.send(.request(.showChatHistory))
    }

    @objc
    private func hideSidebar(_: NSMenuItem) {
        store.send(.sidebar(.view(.setSidebarVisible(false))))
    }

    @objc
    private func showSidebar(_: NSMenuItem) {
        store.send(.sidebar(.view(.setSidebarVisible(true))))
    }

    @objc
    private func toggleSidebar(_: NSMenuItem) {
        store.send(.request(.toggleSidebar))
    }
}

@MainActor
private final class FileManagerHostMaterialTuningState: ObservableObject {
    @Published var configuration = FileManagerHostFixture.MaterialConfiguration.hostDefault {
        didSet {
            onUpdate?(configuration)
        }
    }

    var onUpdate: ((FileManagerHostFixture.MaterialConfiguration) -> Void)?

    func update(_ mutate: (inout FileManagerHostFixture.MaterialConfiguration) -> Void) {
        var updatedConfiguration = configuration
        mutate(&updatedConfiguration)
        configuration = updatedConfiguration
    }

    func reset() {
        configuration = .hostDefault
    }
}

private struct FileManagerHostMaterialTuningPanel: View {
    @ObservedObject var tuningState: FileManagerHostMaterialTuningState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Material Tuning")
                .font(.headline)
            FileManagerHostMaterialSurfaceControls(
                title: "Window Shell",
                surface: Binding(
                    get: { tuningState.configuration.windowShell },
                    set: { surface in tuningState.update { $0.windowShell = surface } },
                ),
            )
            Divider()
            FileManagerHostMaterialSurfaceControls(
                title: "Content Background",
                surface: Binding(
                    get: { tuningState.configuration.contentBackground },
                    set: { surface in tuningState.update { $0.contentBackground = surface } },
                ),
            )
            HStack {
                Spacer()
                Button("Reset to Production Defaults") {
                    tuningState.reset()
                }
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

private struct FileManagerHostMaterialSurfaceControls: View {
    let title: String
    @Binding var surface: FileManagerHostFixture.MaterialConfiguration.Surface

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Picker("Material", selection: material) {
                ForEach(FileManagerHostMaterialOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Picker("Blending", selection: blendingMode) {
                ForEach(FileManagerHostBlendingModeOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            HStack {
                Text("Alpha")
                Slider(value: $surface.alphaValue, in: 0 ... 1)
                Text(surface.alphaValue, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    private var material: Binding<FileManagerHostMaterialOption> {
        Binding(
            get: { FileManagerHostMaterialOption(material: surface.material) ?? .sidebar },
            set: { surface.material = $0.material },
        )
    }

    private var blendingMode: Binding<FileManagerHostBlendingModeOption> {
        Binding(
            get: { FileManagerHostBlendingModeOption(blendingMode: surface.blendingMode) ?? .behindWindow },
            set: { surface.blendingMode = $0.blendingMode },
        )
    }
}

private enum FileManagerHostMaterialOption: String, CaseIterable, Identifiable {
    case sidebar, windowBackground, underWindowBackground, contentBackground
    case headerView, hudWindow, fullScreenUI, titlebar, selection, menu, popover, sheet, toolTip
    case underPageBackground

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .sidebar: "Sidebar"
        case .windowBackground: "Window Background"
        case .underWindowBackground: "Under Window Background"
        case .contentBackground: "Content Background"
        case .headerView: "Header View"
        case .hudWindow: "HUD Window"
        case .fullScreenUI: "Full Screen UI"
        case .titlebar: "Titlebar"
        case .selection: "Selection"
        case .menu: "Menu"
        case .popover: "Popover"
        case .sheet: "Sheet"
        case .toolTip: "Tool Tip"
        case .underPageBackground: "Under Page Background"
        }
    }

    var material: NSVisualEffectView.Material {
        switch self {
        case .sidebar: .sidebar
        case .windowBackground: .windowBackground
        case .underWindowBackground: .underWindowBackground
        case .contentBackground: .contentBackground
        case .headerView: .headerView
        case .hudWindow: .hudWindow
        case .fullScreenUI: .fullScreenUI
        case .titlebar: .titlebar
        case .selection: .selection
        case .menu: .menu
        case .popover: .popover
        case .sheet: .sheet
        case .toolTip: .toolTip
        case .underPageBackground: .underPageBackground
        }
    }

    init?(material: NSVisualEffectView.Material) {
        switch material {
        case .sidebar: self = .sidebar
        case .windowBackground: self = .windowBackground
        case .underWindowBackground: self = .underWindowBackground
        case .contentBackground: self = .contentBackground
        case .headerView: self = .headerView
        case .hudWindow: self = .hudWindow
        case .fullScreenUI: self = .fullScreenUI
        case .titlebar: self = .titlebar
        case .selection: self = .selection
        case .menu: self = .menu
        case .popover: self = .popover
        case .sheet: self = .sheet
        case .toolTip: self = .toolTip
        case .underPageBackground: self = .underPageBackground
        default: return nil
        }
    }
}

private enum FileManagerHostBlendingModeOption: String, CaseIterable, Identifiable {
    case behindWindow, withinWindow

    var id: String {
        rawValue
    }

    var title: String {
        rawValue == "behindWindow" ? "Behind Window" : "Within Window"
    }

    var blendingMode: NSVisualEffectView.BlendingMode {
        self == .behindWindow ? .behindWindow : .withinWindow
    }

    init?(blendingMode: NSVisualEffectView.BlendingMode) {
        switch blendingMode {
        case .behindWindow: self = .behindWindow
        case .withinWindow: self = .withinWindow
        @unknown default: return nil
        }
    }
}

private struct FileManagerHostScenarioPicker: View {
    @State private var preset: FileManagerHostPreset
    let onSelect: (FileManagerHostPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scenario")
                .font(.headline)
            Picker("Preset", selection: $preset) {
                ForEach(FileManagerHostPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .onChange(of: preset) { new in
                onSelect(new)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

extension FileManagerHostScenarioPicker {
    init(
        initialPreset: FileManagerHostPreset,
        onSelect: @escaping (FileManagerHostPreset) -> Void,
    ) {
        self.onSelect = onSelect
        _preset = State(initialValue: initialPreset)
    }
}
