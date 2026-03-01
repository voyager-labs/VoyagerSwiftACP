import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
@Reducer
private struct FileManagerCommandHarnessFeature {
    @MainActor
    @ObservableState
    struct State: Equatable {
        var window = FileManagerFeature.State()
    }

    enum Action: Equatable {
        case window(FileManagerWindowAction)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.window(lhsAction), .window(rhsAction)):
                switch (lhsAction, rhsAction) {
                case (.request(.newFolder), .request(.newFolder)): true
                case (.request(.paste), .request(.paste)): true
                case (.request(.toggleSidebar), .request(.toggleSidebar)): true
                case (.request(.toggleComposer), .request(.toggleComposer)): true
                case let (.content(.entries(.createNewFolder(lhsPath))), .content(.entries(.createNewFolder(rhsPath)))):
                    lhsPath == rhsPath
                case let (.content(.entries(.pasteItems(lhsPath))), .content(.entries(.pasteItems(rhsPath)))):
                    lhsPath == rhsPath
                case let (
                    .content(.composer(.setPresented(lhsPresented))),
                    .content(.composer(.setPresented(rhsPresented))),
                ):
                    lhsPresented == rhsPresented
                case let (.sidebar(.setSidebarVisible(lhsVisible)), .sidebar(.setSidebarVisible(rhsVisible))):
                    lhsVisible == rhsVisible
                default:
                    false
                }
            }
        }
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.window, action: \.window) {
            FileManagerFeature()
        }
    }
}

@MainActor
final class FileManagerWindowCommandRoutingTests: XCTestCase {
    func testNewFolderCommandUsesCurrentNavigationPath() async {
        let expectedPath = "/tmp/voyager"
        var initialState = FileManagerCommandHarnessFeature.State()
        initialState.window.content.navigation.seedInitialFolderPath(expectedPath)

        let store = TestStore(initialState: initialState) {
            FileManagerCommandHarnessFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.window(.request(.newFolder)))
        await store.receive(.window(.content(.entries(.createNewFolder(currentPath: expectedPath)))))
    }

    func testPasteCommandUsesCurrentNavigationPath() async {
        let expectedPath = "/tmp/voyager"
        var initialState = FileManagerCommandHarnessFeature.State()
        initialState.window.content.navigation.seedInitialFolderPath(expectedPath)

        let store = TestStore(initialState: initialState) {
            FileManagerCommandHarnessFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.window(.request(.paste)))
        await store.receive(.window(.content(.entries(.pasteItems(destinationPath: expectedPath)))))
    }

    func testToggleSidebarCommandUsesCurrentSidebarState() async {
        var initialState = FileManagerCommandHarnessFeature.State()
        initialState.window.sidebar.sidebarVisible = true

        let store = TestStore(initialState: initialState) {
            FileManagerCommandHarnessFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.window(.request(.toggleSidebar)))
        await store.receive(.window(.sidebar(.setSidebarVisible(false))))
    }

    func testToggleComposerCommandUsesCurrentComposerState() async {
        var initialState = FileManagerCommandHarnessFeature.State()
        initialState.window.content.composer.isPresented = false

        let store = TestStore(initialState: initialState) {
            FileManagerCommandHarnessFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.window(.request(.toggleComposer)))
        await store.receive(.window(.content(.composer(.setPresented(true)))))
    }
}
