import AppKit
import ComposableArchitecture
import Dependencies
import Foundation
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared

// MARK: - PasteboardClient.noOp

extension PasteboardClient {
    /// No-op pasteboard: all operations succeed silently without touching the system pasteboard.
    static let noOp = PasteboardClient(
        changeCount: { 0 },
        clearContents: {},
        writeObjects: { _ in true },
        readObjects: { _, _ in nil },
        setString: { _, _ in true },
        string: { _ in nil },
    )
}

// MARK: - Test Store Factory

@MainActor
enum EntryOperationsTestSupport {
    /// Creates a `TestStore` with safe baseline dependencies for EntryOperations tests.
    ///
    /// Baseline dependencies:
    /// - `entryFileOpsClient`: `.previewValue` (no side effects)
    /// - `entryOpenClient`: `.previewValue` (no side effects)
    /// - `entryQuickLookClient`: `.previewValue` (no side effects)
    /// - `pasteboardClient`: `.noOp` (silent, no system pasteboard)
    /// - `undoManagerClient`: no-op (registerUndo/undo/redo do nothing)
    /// - `trashMetadataStoreClient`: `.testValue` (in-memory storage)
    ///
    /// Use `configure` to override specific dependencies per test.
    static func makeStore(
        initialState: EntryOperationsFeature.State = .init(),
        configure: (inout DependencyValues) -> Void = { _ in },
    ) -> TestStore<EntryOperationsFeature.State, EntryOperationsFeature.Action> {
        TestStore(initialState: initialState) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.entryOpenClient = .previewValue
            $0.entryQuickLookClient = .previewValue
            $0.pasteboardClient = .noOp
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _ in },
                undo: { _ in .init(didInvoke: false, availability: .init()) },
                redo: { _ in .init(didInvoke: false, availability: .init()) },
            )
            $0.trashMetadataStoreClient = .testValue
            configure(&$0)
        }
    }

    static func makeObservedStore(
        initialState: EntryOperationsFeature.State = .init(),
        observeAction: @escaping @Sendable (EntryOperationsFeature.Action) -> Void,
        configure: (inout DependencyValues) -> Void = { _ in },
    ) -> TestStore<EntryOperationsFeature.State, EntryOperationsFeature.Action> {
        TestStore(initialState: initialState) {
            CombineReducers {
                EntryOperationsFeature()
                Reduce { _, action in
                    observeAction(action)
                    return .none
                }
            }
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.entryOpenClient = .previewValue
            $0.entryQuickLookClient = .previewValue
            $0.pasteboardClient = .noOp
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _ in },
                undo: { _ in .init(didInvoke: false, availability: .init()) },
                redo: { _ in .init(didInvoke: false, availability: .init()) },
            )
            $0.trashMetadataStoreClient = .testValue
            configure(&$0)
        }
    }
}
