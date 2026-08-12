import Foundation

public extension UndoManagerClient {
    static func live(
        registry: FileOperationUndoManagerRegistry,
        resolveScope: @escaping @MainActor @Sendable (_ windowID: UUID) -> UndoManagerScope?,
    ) -> UndoManagerClient {
        .init(
            registerUndo: { windowID, ownerID, record in
                await MainActor.run {
                    guard let scope = resolveScope(windowID) else { return }
                    registry.registerCompatibilityUndo(scope, ownerID: ownerID, record: record)
                }
            },
            events: { registry.compatibilityEvents(windowID: $0) },
            undo: { windowID, expectedTarget in
                await MainActor.run {
                    registry.performCompatibilityUndoRedo(
                        windowID.flatMap(resolveScope),
                        expectedTarget: expectedTarget,
                        direction: .undo,
                    )
                }
            },
            redo: { windowID, expectedTarget in
                await MainActor.run {
                    registry.performCompatibilityUndoRedo(
                        windowID.flatMap(resolveScope),
                        expectedTarget: expectedTarget,
                        direction: .redo,
                    )
                }
            },
            availability: { windowID in
                await MainActor.run {
                    registry.compatibilityAvailability(windowID.flatMap(resolveScope))
                }
            },
            invalidateOwner: { windowID, ownerID in
                await MainActor.run {
                    registry.invalidateCompatibilityOwner(resolveScope(windowID), ownerID: ownerID)
                }
            },
            invalidateWindow: { windowID in
                await MainActor.run {
                    registry.invalidateCompatibilityWindow(windowID)
                }
            },
        )
    }
}
