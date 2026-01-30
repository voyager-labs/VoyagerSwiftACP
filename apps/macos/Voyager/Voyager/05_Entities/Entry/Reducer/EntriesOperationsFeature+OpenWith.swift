import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

extension EntriesOperationsFeature {
    func selectApplicationAndOpenFile(
        for file: Entry,
        defaultChecked: Bool,
        workspaceClient: WorkspaceClient,
    ) -> Effect<Action> {
        selectApplicationAndOpenFile(for: [file], defaultChecked: defaultChecked, workspaceClient: workspaceClient)
    }

    func selectApplicationAndOpenFile(
        for files: [Entry],
        defaultChecked: Bool,
        workspaceClient: WorkspaceClient,
    ) -> Effect<Action> {
        let fileURLs = files.map { URL(fileURLWithPath: $0.fullPath) }

        return .run { [workspaceClient] send in
            guard let selection = await selectApplication(
                for: fileURLs,
                workspaceClient: workspaceClient,
                defaultChecked: defaultChecked,
            ) else { return }

            for file in files {
                let effects = await MainActor.run { () -> [EntriesOperationsFeature.Action] in
                    var actions: [EntriesOperationsFeature.Action] = []

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

                    return actions
                }
                for effect in effects {
                    await send(effect)
                }
            }
        }
    }

    private class OpenWithPanelDelegate: NSObject, NSOpenSavePanelDelegate {
        let fileURL: URL?
        let fileURLs: [URL]?
        var enableMode: OpenWithEnableMode
        weak var panel: NSOpenPanel?
        let workspaceClient: WorkspaceClient

        init(
            workspaceClient: WorkspaceClient,
            fileURL: URL? = nil,
            fileURLs: [URL]? = nil,
            enableMode: OpenWithEnableMode = .recommended,
        ) {
            self.fileURL = fileURL
            self.fileURLs = fileURLs
            self.enableMode = enableMode
            self.workspaceClient = workspaceClient
            super.init()
        }

        func panel(_: Any, shouldEnable url: URL) -> Bool {
            guard url.pathExtension == "app" else { return false }
            guard enableMode == .recommended else { return true }

            if let fileURL {
                let supportedApps = workspaceClient.urlsForApplications(fileURL)
                return supportedApps.contains(url)
            } else if let fileURLs {
                for fileURL in fileURLs {
                    let supportedApps = workspaceClient.urlsForApplications(fileURL)
                    if !supportedApps.contains(url) {
                        return false
                    }
                }
                return true
            }
            return false
        }

        @objc
        func enableModeChanged(_ sender: NSPopUpButton) {
            enableMode = OpenWithEnableMode(rawValue: sender.indexOfSelectedItem) ?? .recommended
            panel?.validateVisibleColumns()
        }
    }

    private struct ApplicationSelection {
        let bundleID: String
        let type: UTType?
        let setAsDefault: Bool
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

    @MainActor
    private func selectApplication(
        for itemURL: URL,
        workspaceClient: WorkspaceClient,
        defaultChecked: Bool = false,
    ) -> ApplicationSelection? {
        selectApplication(
            fileURL: itemURL,
            fileURLs: nil,
            message: "Choose an application to open the document \"\(itemURL.lastPathComponent)\".",
            defaultChecked: defaultChecked,
            workspaceClient: workspaceClient,
        )
    }

    @MainActor
    private func selectApplication(
        for fileURLs: [URL],
        workspaceClient: WorkspaceClient,
        defaultChecked: Bool = false,
    ) -> ApplicationSelection? {
        selectApplication(
            fileURL: nil,
            fileURLs: fileURLs,
            message: "Choose an application to open \(fileURLs.count) items.",
            defaultChecked: defaultChecked,
            workspaceClient: workspaceClient,
        )
    }

    @MainActor
    private func selectApplication(
        fileURL: URL?,
        fileURLs: [URL]?,
        message: String,
        defaultChecked: Bool,
        workspaceClient: WorkspaceClient,
    ) -> ApplicationSelection? {
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
        panel.message = message

        let delegate = OpenWithPanelDelegate(
            workspaceClient: workspaceClient,
            fileURL: fileURL,
            fileURLs: fileURLs,
            enableMode: .recommended,
        )
        panel.delegate = delegate
        delegate.panel = panel

        let (accessoryView, checkbox) = createOpenWithAccessoryView(delegate: delegate, defaultChecked: defaultChecked)
        panel.accessoryView = accessoryView
        panel.isAccessoryViewDisclosed = true

        guard panel.runModal() == .OK, let appURL = panel.url,
              let bundleID = Bundle(url: appURL)?.bundleIdentifier
        else {
            return nil
        }

        let type = (fileURL ?? fileURLs?.first).flatMap { UTType(filenameExtension: $0.pathExtension) }
        return ApplicationSelection(
            bundleID: bundleID,
            type: type,
            setAsDefault: checkbox.state == .on,
        )
    }
}

private enum OpenWithEnableMode: Int {
    case recommended = 0
    case all = 1
}
