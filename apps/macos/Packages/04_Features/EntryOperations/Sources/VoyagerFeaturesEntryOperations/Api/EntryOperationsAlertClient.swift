import ComposableArchitecture

public enum EntryOperationsReplaceContext: Sendable {
    case putBack
    case move
}

public enum EntryOperationsReplaceAlertResponse: Sendable {
    case stop
    case replace
}

public struct EntryOperationsAlertClient: Sendable {
    public var showTrashFileAlert: @Sendable (_ fileName: String, _ hasMoreFiles: Bool) async -> Bool
    public var showRenameConflictAlert: @Sendable (_ itemName: String) async -> Void
    public var showDeleteConfirmationAlert: @Sendable (_ itemNames: [String]) async -> Bool
    public var showEmptyTrashConfirmationAlert: @Sendable (_ itemCount: Int) async -> Bool
    public var showReplaceAlert: @Sendable (
        _ itemName: String,
        _ context: EntryOperationsReplaceContext,
    ) async -> EntryOperationsReplaceAlertResponse
    public var showGetInfoFailureAlert: @Sendable (_ message: String, _ suggestion: String?) async -> Void
    public var showRenameExtensionChangeAlert: @Sendable (_ oldName: String, _ newName: String) async -> Bool

    public nonisolated init(
        showTrashFileAlert: @escaping @Sendable (_ fileName: String, _ hasMoreFiles: Bool) async -> Bool,
        showRenameConflictAlert: @escaping @Sendable (_ itemName: String) async -> Void,
        showDeleteConfirmationAlert: @escaping @Sendable (_ itemNames: [String]) async -> Bool,
        showEmptyTrashConfirmationAlert: @escaping @Sendable (_ itemCount: Int) async -> Bool,
        showReplaceAlert: @escaping @Sendable (
            _ itemName: String,
            _ context: EntryOperationsReplaceContext,
        ) async -> EntryOperationsReplaceAlertResponse,
        showGetInfoFailureAlert: @escaping @Sendable (_ message: String, _ suggestion: String?) async -> Void,
        showRenameExtensionChangeAlert: @escaping @Sendable (_ oldName: String, _ newName: String) async
            -> Bool = { _, _ in true },
    ) {
        self.showTrashFileAlert = showTrashFileAlert
        self.showRenameConflictAlert = showRenameConflictAlert
        self.showDeleteConfirmationAlert = showDeleteConfirmationAlert
        self.showEmptyTrashConfirmationAlert = showEmptyTrashConfirmationAlert
        self.showReplaceAlert = showReplaceAlert
        self.showGetInfoFailureAlert = showGetInfoFailureAlert
        self.showRenameExtensionChangeAlert = showRenameExtensionChangeAlert
    }
}

extension EntryOperationsAlertClient: DependencyKey {
    public nonisolated static var liveValue: EntryOperationsAlertClient {
        EntryOperationsAlertClient(
            showTrashFileAlert: { fileName, hasMoreFiles in
                await MainActor.run {
                    EntryOperationsAlertPresenter.showTrashFileAlert(
                        fileName: fileName,
                        hasMoreFiles: hasMoreFiles,
                    )
                }
            },
            showRenameConflictAlert: { itemName in
                await MainActor.run {
                    EntryOperationsAlertPresenter.showRenameConflictAlert(itemName: itemName)
                }
            },
            showDeleteConfirmationAlert: { itemNames in
                await MainActor.run {
                    EntryOperationsAlertPresenter.showDeleteConfirmationAlert(itemNames: itemNames)
                }
            },
            showEmptyTrashConfirmationAlert: { itemCount in
                await MainActor.run {
                    EntryOperationsAlertPresenter.showEmptyTrashConfirmationAlert(itemCount: itemCount)
                }
            },
            showReplaceAlert: { itemName, context in
                await MainActor.run {
                    EntryOperationsAlertPresenter.showReplaceAlert(
                        itemName: itemName,
                        context: context,
                    )
                }
            },
            showGetInfoFailureAlert: { message, suggestion in
                await MainActor.run {
                    EntryOperationsAlertPresenter.showGetInfoFailureAlert(
                        message: message,
                        suggestion: suggestion,
                    )
                }
            },
            showRenameExtensionChangeAlert: { oldName, newName in
                await MainActor.run {
                    EntryOperationsAlertPresenter.showRenameExtensionChangeAlert(
                        oldName: oldName,
                        newName: newName,
                    )
                }
            },
        )
    }

    public nonisolated static var testValue: EntryOperationsAlertClient {
        EntryOperationsAlertClient(
            showTrashFileAlert: { _, _ in false },
            showRenameConflictAlert: { _ in },
            showDeleteConfirmationAlert: { _ in false },
            showEmptyTrashConfirmationAlert: { _ in false },
            showReplaceAlert: { _, _ in .stop },
            showGetInfoFailureAlert: { _, _ in },
            showRenameExtensionChangeAlert: { _, _ in true },
        )
    }

    public nonisolated static var previewValue: EntryOperationsAlertClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var entryOperationsAlertClient: EntryOperationsAlertClient {
        get { self[EntryOperationsAlertClient.self] }
        set { self[EntryOperationsAlertClient.self] = newValue }
    }
}
