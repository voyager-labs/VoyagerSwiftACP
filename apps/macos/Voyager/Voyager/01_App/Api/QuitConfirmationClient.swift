import ComposableArchitecture

struct QuitConfirmationResult: Equatable, Sendable {
    var shouldQuit: Bool
    var isAlertBeforeQuitEnabled: Bool
}

struct QuitConfirmationClient: Sendable {
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
