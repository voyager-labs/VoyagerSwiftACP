import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

struct OpenWithPanelSelection: Equatable, Sendable {
    let bundleID: String
    let setAsDefault: Bool
}

struct OpenWithPanelClient: Sendable {
    var selectApplication: @Sendable (
        _ fileURLs: [URL],
        _ defaultChecked: Bool,
        _ workspaceClient: WorkspaceClient,
    ) async -> OpenWithPanelSelection?

    nonisolated init(
        selectApplication: @escaping @Sendable (
            _ fileURLs: [URL],
            _ defaultChecked: Bool,
            _ workspaceClient: WorkspaceClient,
        ) async -> OpenWithPanelSelection?,
    ) {
        self.selectApplication = selectApplication
    }
}

extension OpenWithPanelClient: DependencyKey {
    nonisolated static var liveValue: OpenWithPanelClient {
        OpenWithPanelClient(
            selectApplication: { fileURLs, defaultChecked, workspaceClient in
                await MainActor.run {
                    selectOpenWithApplication(
                        for: fileURLs,
                        defaultChecked: defaultChecked,
                        workspaceClient: workspaceClient,
                    )
                }
            },
        )
    }

    nonisolated static var testValue: OpenWithPanelClient {
        OpenWithPanelClient(
            selectApplication: { _, _, _ in nil },
        )
    }

    nonisolated static var previewValue: OpenWithPanelClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var openWithPanelClient: OpenWithPanelClient {
        get { self[OpenWithPanelClient.self] }
        set { self[OpenWithPanelClient.self] = newValue }
    }
}

@MainActor
private func selectOpenWithApplication(
    for fileURLs: [URL],
    defaultChecked: Bool,
    workspaceClient: WorkspaceClient,
) -> OpenWithPanelSelection? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    if #available(macOS 13.0, *) {
        panel.allowedContentTypes = [.application]
    } else {
        panel.allowedFileTypes = ["app"]
    }

    panel.prompt = "Open"
    panel.message = "Choose an application to open \(fileURLs.count) items."

    let delegate = OpenWithPanelDelegate(
        fileURLs: fileURLs,
        workspaceClient: workspaceClient,
        enableMode: .recommended,
    )
    panel.delegate = delegate
    delegate.panel = panel

    let (accessoryView, checkbox) = createOpenWithAccessoryView(delegate: delegate, defaultChecked: defaultChecked)
    panel.accessoryView = accessoryView
    panel.isAccessoryViewDisclosed = true

    guard panel.runModal() == .OK,
          let appURL = panel.url,
          let bundleID = Bundle(url: appURL)?.bundleIdentifier
    else {
        return nil
    }

    return OpenWithPanelSelection(bundleID: bundleID, setAsDefault: checkbox.state == .on)
}

@MainActor
private func createOpenWithAccessoryView(
    delegate: OpenWithPanelDelegate,
    defaultChecked: Bool,
) -> (view: NSView, checkbox: NSButton) {
    let enableLabel = NSTextField(labelWithString: "Enable:")
    enableLabel.isEditable = false
    enableLabel.isBordered = false
    enableLabel.backgroundColor = .clear
    enableLabel.sizeToFit()

    let enablePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26), pullsDown: false)
    enablePopup.addItems(withTitles: ["Recommended Applications", "All Applications"])
    enablePopup.target = delegate
    enablePopup.action = #selector(OpenWithPanelDelegate.enableModeChanged(_:))

    let enableStack = NSStackView(views: [enableLabel, enablePopup])
    enableStack.orientation = .horizontal
    enableStack.spacing = 8
    enableStack.alignment = .centerY

    let checkbox = NSButton(checkboxWithTitle: "Always Open With", target: nil, action: nil)
    checkbox.state = defaultChecked ? .on : .off
    checkbox.sizeToFit()

    let mainStack = NSStackView(views: [enableStack, checkbox])
    mainStack.orientation = .vertical
    mainStack.spacing = 12
    mainStack.alignment = .centerX

    let fittingSize = mainStack.fittingSize
    mainStack.setFrameSize(fittingSize)

    let accessoryView = NSView()
    accessoryView.translatesAutoresizingMaskIntoConstraints = false
    accessoryView.addSubview(mainStack)

    mainStack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        mainStack.centerXAnchor.constraint(equalTo: accessoryView.centerXAnchor),
        mainStack.centerYAnchor.constraint(equalTo: accessoryView.centerYAnchor),
        accessoryView.heightAnchor.constraint(equalToConstant: fittingSize.height + 20),
    ])

    return (accessoryView, checkbox)
}

private final class OpenWithPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    let fileURLs: [URL]
    let workspaceClient: WorkspaceClient
    var enableMode: OpenWithEnableMode
    weak var panel: NSOpenPanel?

    init(
        fileURLs: [URL],
        workspaceClient: WorkspaceClient,
        enableMode: OpenWithEnableMode,
    ) {
        self.fileURLs = fileURLs
        self.workspaceClient = workspaceClient
        self.enableMode = enableMode
    }

    func panel(_: Any, shouldEnable url: URL) -> Bool {
        guard url.pathExtension == "app" else { return false }
        guard enableMode == .recommended else { return true }

        for fileURL in fileURLs {
            let supportedApps = workspaceClient.urlsForApplications(fileURL)
            if !supportedApps.contains(url) {
                return false
            }
        }

        return true
    }

    @objc
    func enableModeChanged(_ sender: NSPopUpButton) {
        enableMode = OpenWithEnableMode(rawValue: sender.indexOfSelectedItem) ?? .recommended
        panel?.validateVisibleColumns()
    }
}

private enum OpenWithEnableMode: Int {
    case recommended = 0
    case all = 1
}
