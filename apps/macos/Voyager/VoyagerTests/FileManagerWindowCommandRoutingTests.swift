import ComposableArchitecture
@testable import Voyager
import XCTest

@Reducer
private struct FileManagerCommandHarnessFeature {
    @ObservableState
    struct State: Equatable {
        var window = FileManagerFeature.State()
        var lastRoute: Route?
    }

    enum Action {
        case window(FileManagerWindowAction)
    }

    enum Route: Equatable {
        case createNewFolder(path: String)
        case pasteItems(path: String)
        case toggleSidebar(visible: Bool)
        case toggleComposer(presented: Bool)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.window, action: \.window) {
            FileManagerFeature()
        }

        Reduce { state, action in
            switch action {
            case let .window(.content(.entries(.createNewFolder(currentPath)))):
                state.lastRoute = .createNewFolder(path: currentPath)

            case let .window(.content(.entries(.pasteItems(destinationPath)))):
                state.lastRoute = .pasteItems(path: destinationPath)

            case let .window(.sidebar(.setSidebarVisible(visible))):
                state.lastRoute = .toggleSidebar(visible: visible)

            case let .window(.content(.composer(.setPresented(presented)))):
                state.lastRoute = .toggleComposer(presented: presented)

            default:
                break
            }

            return .none
        }
    }
}

@MainActor
final class FileManagerWindowCommandRoutingTests: XCTestCase {
    func testNewFolderCommandUsesCurrentNavigationPath() async {
        let store = TestStore(initialState: FileManagerCommandHarnessFeature.State()) {
            FileManagerCommandHarnessFeature()
        }
        store.exhaustivity = .off

        store.state.window.content.navigation.currentPath = "/tmp/voyager"

        await store.send(.window(.request(.newFolder)))
        await store.finish()

        XCTAssertEqual(store.state.lastRoute, .createNewFolder(path: "/tmp/voyager"))
    }

    func testPasteCommandUsesCurrentNavigationPath() async {
        let store = TestStore(initialState: FileManagerCommandHarnessFeature.State()) {
            FileManagerCommandHarnessFeature()
        }
        store.exhaustivity = .off

        store.state.window.content.navigation.currentPath = "/tmp/voyager"

        await store.send(.window(.request(.paste)))
        await store.finish()

        XCTAssertEqual(store.state.lastRoute, .pasteItems(path: "/tmp/voyager"))
    }

    func testToggleSidebarCommandUsesCurrentSidebarState() async {
        let store = TestStore(initialState: FileManagerCommandHarnessFeature.State()) {
            FileManagerCommandHarnessFeature()
        }
        store.exhaustivity = .off

        store.state.window.sidebar.sidebarVisible = true

        await store.send(.window(.request(.toggleSidebar)))
        await store.finish()

        XCTAssertEqual(store.state.lastRoute, .toggleSidebar(visible: false))
    }

    func testToggleComposerCommandUsesCurrentComposerState() async {
        let store = TestStore(initialState: FileManagerCommandHarnessFeature.State()) {
            FileManagerCommandHarnessFeature()
        }
        store.exhaustivity = .off

        store.state.window.content.composer.isPresented = false

        await store.send(.window(.request(.toggleComposer)))
        await store.finish()

        XCTAssertEqual(store.state.lastRoute, .toggleComposer(presented: true))
    }
}
