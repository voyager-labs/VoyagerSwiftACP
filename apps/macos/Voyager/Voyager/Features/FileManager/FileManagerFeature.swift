import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerFeature {
    @ObservableState
    struct State: Equatable {
        var currentPath: String = FileManager.default.homeDirectoryForCurrentUser.path
        var backHistory: [String] = []
        var forwardHistory: [String] = []
        var fsItems: FSItemsFeature.State = .init()

        var canGoBack: Bool {
            !backHistory.isEmpty
        }

        var canGoForward: Bool {
            !forwardHistory.isEmpty
        }
    }

    enum Action: Equatable {
        case onAppear
        case openItem(id: String)
        case selectTab(at: Int)
        case goBack
        case goForward
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

            case let .selectTab(index):
                return .run { _ in
                    await MainActor.run {
                        guard let window = NSApplication.shared.keyWindow,
                              let tabGroup = window.tabGroup,
                              index < tabGroup.windows.count
                        else {
                            return
                        }
                        tabGroup.windows[index].makeKeyAndOrderFront(nil)
                    }
                }

            case .fsItems:
                return .none
            }
        }
    }
}
