import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerWindowRoutingReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .sidebar(.view(.dropItemsToSidebarFolder(providers, targetURL))):
                .send(.content(.delegate(.dropItemsToSidebarFolder(
                    providers: providers,
                    targetURL: targetURL,
                ))))

            case let .sidebar(.view(.dropItemsToTag(providers, tagName))):
                .send(.content(.delegate(.dropItemsToTag(
                    providers: providers,
                    tagName: tagName,
                ))))

            case .content(.entryOperations(.emptyTrashCompleted)):
                // TODO(VOY-179 후속): 휴지통 비우기 완료 시 창을 닫는 정책이 맞는지 재검토 필요.
                // `closeWindowRequested` delegate 라우트는 있으나 현재 Content에서 명시적 emit 지점이 없음.
                .send(.closeWindow)

            case .content(.delegate(.closeWindowRequested)):
                .send(.closeWindow)

            case .closeWindow:
                .run { _ in
                    await MainActor.run {
                        NSApp.keyWindow?.close()
                    }
                }

            default:
                .none
            }
        }
    }
}
