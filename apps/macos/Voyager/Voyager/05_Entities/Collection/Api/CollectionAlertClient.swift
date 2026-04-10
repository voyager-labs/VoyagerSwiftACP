import AppKit
import ComposableArchitecture

struct CollectionAlertClient: Sendable {
    var showUnsavedNavigationAlert: @Sendable () async -> CollectionNavigationChoice
    var showCollectionOpenErrorAlert: @Sendable (_ title: String, _ message: String) async -> Void

    nonisolated init(
        showUnsavedNavigationAlert: @escaping @Sendable () async -> CollectionNavigationChoice,
        showCollectionOpenErrorAlert: @escaping @Sendable (_ title: String, _ message: String) async -> Void,
    ) {
        self.showUnsavedNavigationAlert = showUnsavedNavigationAlert
        self.showCollectionOpenErrorAlert = showCollectionOpenErrorAlert
    }
}

extension CollectionAlertClient: DependencyKey {
    nonisolated static var liveValue: CollectionAlertClient {
        CollectionAlertClient(
            showUnsavedNavigationAlert: {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Unsaved Filters"
                    alert.informativeText = "You have unsaved filter changes. What would you like to do?"
                    alert.addButton(withTitle: "Save")
                    alert.addButton(withTitle: "Don't Save")
                    alert.addButton(withTitle: "Cancel")

                    let response = alert.runModal()
                    switch response {
                    case .alertFirstButtonReturn:
                        return .save
                    case .alertSecondButtonReturn:
                        return .discard
                    default:
                        return .cancel
                    }
                }
            },
            showCollectionOpenErrorAlert: { title, message in
                await MainActor.run {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = title
                    alert.informativeText = message
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            },
        )
    }

    nonisolated static var testValue: CollectionAlertClient {
        CollectionAlertClient(
            showUnsavedNavigationAlert: { .cancel },
            showCollectionOpenErrorAlert: { _, _ in },
        )
    }

    nonisolated static var previewValue: CollectionAlertClient {
        CollectionAlertClient(
            showUnsavedNavigationAlert: { .cancel },
            showCollectionOpenErrorAlert: { _, _ in },
        )
    }
}

extension DependencyValues {
    nonisolated var collectionAlertClient: CollectionAlertClient {
        get { self[CollectionAlertClient.self] }
        set { self[CollectionAlertClient.self] = newValue }
    }
}
