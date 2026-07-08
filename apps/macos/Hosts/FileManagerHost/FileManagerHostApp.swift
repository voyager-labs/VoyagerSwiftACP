import AppKit
import Combine
import SwiftUI
import VoyagerPagesFileManager

@MainActor
private enum FileManagerHostSmokeMode {
    static var isEnabled: Bool {
        // TODO(VOY-432): ProcessInfo 대신 Dotenv 사용 검토 — https://linear.app/voyager-fm/issue/VOY-432
        ProcessInfo.processInfo.environment["FILE_MANAGER_HOST_SMOKE"] == "1"
    }

    static func runIfNeeded() {
        guard isEnabled else { return }

        _ = NSApplication.shared
        let windowController = FileManagerHostFixture.makeWindowController()
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
    private var windowController: NSWindowController?

    func applicationDidFinishLaunching(_: Notification) {
        showWindow(for: initialPreset)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func selectPreset(_ preset: FileManagerHostPreset) {
        windowController?.close()
        windowController = nil
        initialPreset = preset
        showWindow(for: preset)
    }

    private func showWindow(for preset: FileManagerHostPreset) {
        let controller = FileManagerHostFixture.makeWindowController(preset: preset)
        windowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
