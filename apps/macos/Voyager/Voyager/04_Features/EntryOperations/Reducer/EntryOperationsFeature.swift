import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@Reducer
struct EntryOperationsFeature {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    var body: some Reducer<State, Action> {
        CombineReducers {
            EntryOperationsMetricsReducer()
            EntryOperationsLifecycleReducer()
            EntryUndoRedoOperationsReducer()
            EntryOpenOperationsReducer()
            EntryOpenWithOperationsReducer()
            EntryEditOperationsReducer()
            EntryClipboardOperationsReducer()
            EntryTrashOperationsReducer()
            EntryArchiveOperationsReducer()
            EntryTaggingOperationsReducer()
        }
    }
}

enum EntryOperationsReplaceContext: Sendable {
    case putBack
    case move
}

enum EntryOperationsReplaceAlertResponse: Sendable {
    case stop
    case replace
}

struct EntryOperationsAlertClient: Sendable {
    var showTrashFileAlert: @Sendable (_ fileName: String, _ hasMoreFiles: Bool) async -> Bool
    var showRenameConflictAlert: @Sendable (_ itemName: String) async -> Void
    var showDeleteConfirmationAlert: @Sendable (_ itemNames: [String]) async -> Bool
    var showEmptyTrashConfirmationAlert: @Sendable (_ itemCount: Int) async -> Bool
    var showReplaceAlert: @Sendable (
        _ itemName: String,
        _ context: EntryOperationsReplaceContext,
    ) async -> EntryOperationsReplaceAlertResponse
    var showGetInfoFailureAlert: @Sendable (_ message: String, _ suggestion: String?) async -> Void

    nonisolated init(
        showTrashFileAlert: @escaping @Sendable (_ fileName: String, _ hasMoreFiles: Bool) async -> Bool,
        showRenameConflictAlert: @escaping @Sendable (_ itemName: String) async -> Void,
        showDeleteConfirmationAlert: @escaping @Sendable (_ itemNames: [String]) async -> Bool,
        showEmptyTrashConfirmationAlert: @escaping @Sendable (_ itemCount: Int) async -> Bool,
        showReplaceAlert: @escaping @Sendable (
            _ itemName: String,
            _ context: EntryOperationsReplaceContext,
        ) async -> EntryOperationsReplaceAlertResponse,
        showGetInfoFailureAlert: @escaping @Sendable (_ message: String, _ suggestion: String?) async -> Void,
    ) {
        self.showTrashFileAlert = showTrashFileAlert
        self.showRenameConflictAlert = showRenameConflictAlert
        self.showDeleteConfirmationAlert = showDeleteConfirmationAlert
        self.showEmptyTrashConfirmationAlert = showEmptyTrashConfirmationAlert
        self.showReplaceAlert = showReplaceAlert
        self.showGetInfoFailureAlert = showGetInfoFailureAlert
    }
}

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

extension EntryOperationsAlertClient: DependencyKey {
    nonisolated static var liveValue: EntryOperationsAlertClient {
        EntryOperationsAlertClient(
            showTrashFileAlert: { fileName, hasMoreFiles in
                await MainActor.run {
                    showEntryOperationsTrashFileAlert(fileName: fileName, hasMoreFiles: hasMoreFiles)
                }
            },
            showRenameConflictAlert: { itemName in
                await MainActor.run {
                    showEntryOperationsRenameConflictAlert(itemName: itemName)
                }
            },
            showDeleteConfirmationAlert: { itemNames in
                await MainActor.run {
                    showEntryOperationsDeleteConfirmationAlert(itemNames: itemNames)
                }
            },
            showEmptyTrashConfirmationAlert: { itemCount in
                await MainActor.run {
                    showEntryOperationsEmptyTrashConfirmationAlert(itemCount: itemCount)
                }
            },
            showReplaceAlert: { itemName, context in
                await MainActor.run {
                    showEntryOperationsReplaceAlert(
                        itemName: itemName,
                        context: context,
                    )
                }
            },
            showGetInfoFailureAlert: { message, suggestion in
                await MainActor.run {
                    showEntryOperationsGetInfoFailureAlert(message: message, suggestion: suggestion)
                }
            },
        )
    }

    nonisolated static var testValue: EntryOperationsAlertClient {
        EntryOperationsAlertClient(
            showTrashFileAlert: { _, _ in false },
            showRenameConflictAlert: { _ in },
            showDeleteConfirmationAlert: { _ in false },
            showEmptyTrashConfirmationAlert: { _ in false },
            showReplaceAlert: { _, _ in .stop },
            showGetInfoFailureAlert: { _, _ in },
        )
    }

    nonisolated static var previewValue: EntryOperationsAlertClient {
        testValue
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
    nonisolated var entryOperationsAlertClient: EntryOperationsAlertClient {
        get { self[EntryOperationsAlertClient.self] }
        set { self[EntryOperationsAlertClient.self] = newValue }
    }

    nonisolated var openWithPanelClient: OpenWithPanelClient {
        get { self[OpenWithPanelClient.self] }
        set { self[OpenWithPanelClient.self] = newValue }
    }
}

@MainActor
private func showEntryOperationsRenameConflictAlert(itemName: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "The name \"\(itemName)\" is already taken."
    alert.informativeText = "Please choose a different name."
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

@MainActor
private func showEntryOperationsDeleteConfirmationAlert(itemNames: [String]) -> Bool {
    let alert = NSAlert()

    if itemNames.count == 1 {
        alert.messageText = "Are you sure you want to delete \"\(itemNames[0])\"?"
    } else {
        alert.messageText = "Are you sure you want to delete \(itemNames.count) items?"
    }
    alert.informativeText = "This item will be deleted immediately. You can't undo this action."

    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")

    alert.alertStyle = .critical
    alert.buttons[0].hasDestructiveAction = true

    let response = alert.runModal()
    return response == .alertFirstButtonReturn
}

@MainActor
private func showEntryOperationsEmptyTrashConfirmationAlert(itemCount: Int) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .informational

    if let trashIcon = NSImage(systemSymbolName: "trash", accessibilityDescription: "Trash") {
        alert.icon = trashIcon
    }

    if itemCount == 0 {
        alert.messageText = "The Trash is empty."
        alert.informativeText = "There are no items to delete."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        return false
    }

    if itemCount == 1 {
        alert.messageText = "Are you sure you want to permanently erase the item in the Trash?"
    } else {
        alert.messageText = "Are you sure you want to permanently erase the \(itemCount) items in the Trash?"
    }

    alert.informativeText = "You can't undo this action."
    alert.addButton(withTitle: "Empty Trash")
    alert.addButton(withTitle: "Cancel")
    alert.buttons[0].hasDestructiveAction = true

    let response = alert.runModal()
    return response == .alertFirstButtonReturn
}

@MainActor
private func showEntryOperationsReplaceAlert(
    itemName: String,
    context: EntryOperationsReplaceContext,
) -> EntryOperationsReplaceAlertResponse {
    let alert = NSAlert()
    alert.alertStyle = .warning

    switch context {
    case .putBack:
        alert.messageText = "A newer item named \"\(itemName)\" already exists in this location. Do you want to replace it with the older one you're moving?"
    case .move:
        alert.messageText = "An older item named \"\(itemName)\" already exists in this location. Do you want to replace it with the newer one you're moving?"
    }

    alert.addButton(withTitle: "Stop")
    alert.addButton(withTitle: "Replace")

    let response = alert.runModal()
    return response == .alertFirstButtonReturn ? .stop : .replace
}

@MainActor
private func showEntryOperationsTrashFileAlert(fileName: String, hasMoreFiles: Bool) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.icon = NSImage(named: NSImage.cautionName)
    alert.messageText = "The document \"\(fileName)\" can't be opened because it's in the Trash."
    alert.informativeText = "To use this item, first drag it out of the Trash."

    if hasMoreFiles {
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    alert.addButton(withTitle: "OK")
    alert.runModal()
    return false
}

@MainActor
private func showEntryOperationsGetInfoFailureAlert(message: String, suggestion: String?) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = message
    alert.informativeText = suggestion ?? "Please try again."
    alert.addButton(withTitle: "OK")
    alert.runModal()
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
