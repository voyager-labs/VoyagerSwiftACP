import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerFeature {
    static func makeWindowTitle(for path: String) -> String {
        if path == "/" {
            return FileManager.default.displayName(atPath: "/")
        }
        return FileManager.default.displayName(atPath: path)
    }

    @ObservableState
    struct State: Equatable {
        var currentPath: String = Settings.shared.defaultTabPath
        var backHistory: [String] = []
        var forwardHistory: [String] = []
        var fsItems: FSItemsFeature.State = .init()

        var canGoBack: Bool {
            !backHistory.isEmpty
        }

        var canGoForward: Bool {
            !forwardHistory.isEmpty
        }

        var canGoToEnclosingDirectory: Bool {
            let url = URL(fileURLWithPath: currentPath)
            let parent = url.deletingLastPathComponent()
            return parent.path != currentPath && currentPath != "/"
        }

        var pathComponents: [(name: String, fullPath: String)] {
            var result: [(String, String)] = []
            let fileManager = FileManager.default

            if currentPath.hasPrefix("/") {
                result.append((fileManager.displayName(atPath: "/"), "/"))
            }

            let components = currentPath.split(separator: "/").map(String.init)
            var accumulated = "/"

            for component in components {
                accumulated += component
                result.append((fileManager.displayName(atPath: accumulated), accumulated))
                accumulated += "/"
            }

            return result
        }

        var windowTitle: String {
            FileManagerFeature.makeWindowTitle(for: currentPath)
        }
    }

    enum Action: Equatable {
        case onAppear
        case navigateTo(String)
        case openItem(id: String)
        case goBack
        case goForward
        case goToEnclosingDirectory
        case fsItems(FSItemsFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.fsItems, action: \.fsItems) {
            FSItemsFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.fsItems(.loadItems(path: state.currentPath)))

            case let .navigateTo(path):
                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.currentPath = path
                return .send(.fsItems(.loadItems(path: path)))

            case let .openItem(id):
                guard let item = state.fsItems.items.first(where: { $0.id == id }) else {
                    return .none
                }

                if item.isDirectory {
                    state.backHistory.append(state.currentPath)
                    state.forwardHistory = []
                    state.currentPath = item.fullPath
                    return .send(.fsItems(.loadItems(path: item.fullPath)))
                } else {
                    return .none
                }

            case .goBack:
                guard let previousPath = state.backHistory.popLast() else {
                    return .none
                }
                state.forwardHistory.append(state.currentPath)
                state.currentPath = previousPath
                return .send(.fsItems(.loadItems(path: previousPath)))

            case .goForward:
                guard let nextPath = state.forwardHistory.popLast() else {
                    return .none
                }
                state.backHistory.append(state.currentPath)
                state.currentPath = nextPath
                return .send(.fsItems(.loadItems(path: nextPath)))

            case .goToEnclosingDirectory:
                let url = URL(fileURLWithPath: state.currentPath)
                let parentURL = url.deletingLastPathComponent()

                guard parentURL.path != state.currentPath else {
                    return .none
                }

                state.backHistory.append(state.currentPath)
                state.forwardHistory = []
                state.currentPath = parentURL.path

                return .send(.fsItems(.loadItems(path: parentURL.path)))

            case .fsItems:
                return .none
            }
        }
    }
}
