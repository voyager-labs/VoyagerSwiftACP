import ComposableArchitecture
import Foundation

struct QuitConfirmationResult: Equatable {
    var shouldQuit: Bool
    var isAlertBeforeQuitEnabled: Bool
}

struct QuitConfirmationClient {
    var confirmQuit: @Sendable (_ isIndexingInProgress: Bool, _ isAlertBeforeQuitEnabled: Bool) async
        -> QuitConfirmationResult

    nonisolated init(
        confirmQuit: @escaping @Sendable (
            _ isIndexingInProgress: Bool,
            _ isAlertBeforeQuitEnabled: Bool,
        ) async -> QuitConfirmationResult,
    ) {
        self.confirmQuit = confirmQuit
    }
}

extension QuitConfirmationClient: DependencyKey {
    nonisolated static var liveValue: QuitConfirmationClient {
        .init(confirmQuit: { isIndexingInProgress, isAlertBeforeQuitEnabled in
            await MainActor.run {
                let result = QuitConfirmationPresenter.confirmQuit(
                    isIndexingInProgress: isIndexingInProgress,
                    isAlertBeforeQuitEnabled: isAlertBeforeQuitEnabled,
                )
                return QuitConfirmationResult(
                    shouldQuit: result.shouldQuit,
                    isAlertBeforeQuitEnabled: result.isAlertBeforeQuitEnabled,
                )
            }
        })
    }

    nonisolated static var testValue: QuitConfirmationClient {
        .init(confirmQuit: { _, isAlertBeforeQuitEnabled in
            QuitConfirmationResult(
                shouldQuit: true,
                isAlertBeforeQuitEnabled: isAlertBeforeQuitEnabled,
            )
        })
    }

    nonisolated static var previewValue: QuitConfirmationClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var quitConfirmationClient: QuitConfirmationClient {
        get { self[QuitConfirmationClient.self] }
        set { self[QuitConfirmationClient.self] = newValue }
    }
}

struct AttachmentPickerClient: Sendable {
    var pickAttachments: @Sendable () async -> [URL]

    nonisolated init(pickAttachments: @escaping @Sendable () async -> [URL]) {
        self.pickAttachments = pickAttachments
    }
}

extension AttachmentPickerClient: DependencyKey {
    nonisolated static var liveValue: AttachmentPickerClient {
        .init(pickAttachments: {
            await MainActor.run {
                AttachmentPickerPresenter.pickAttachments()
            }
        })
    }

    nonisolated static var testValue: AttachmentPickerClient {
        .init(pickAttachments: { [] })
    }

    nonisolated static var previewValue: AttachmentPickerClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var attachmentPickerClient: AttachmentPickerClient {
        get { self[AttachmentPickerClient.self] }
        set { self[AttachmentPickerClient.self] = newValue }
    }
}
