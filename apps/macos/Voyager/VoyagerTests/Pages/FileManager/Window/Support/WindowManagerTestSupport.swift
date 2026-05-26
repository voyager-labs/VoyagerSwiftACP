import ComposableArchitecture
import XCTest

@testable import Voyager

// WindowManagerTests 공용 테스트 서포트.

enum WindowManagerTestSupport {
    enum Spec {
        static let focusedPath = "/focused"
        static let backgroundPath = "/background"
        static let firstPath = "/a"
        static let secondPath = "/b"
        static let tempPath = "/tmp"
    }

    static func makeStore(
        initialState: WindowManagerFeature.State = WindowManagerFeature.State(),
        uuid: UUID? = nil,
        onboardingRequired: Bool = false,
        configureDependencies: ((inout DependencyValues) -> Void)? = nil,
    ) -> TestStore<WindowManagerFeature.State, WindowManagerFeature.Action> {
        TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            if let uuid {
                $0.uuid = .constant(uuid)
            }
            $0.onboardingWindowClient.showIfNeeded = { onboardingRequired }
            configureDependencies?(&$0)
        }
    }

    static func makeState(
        focusedID: UUID?,
        windows: [(UUID, String?)],
    ) -> WindowManagerFeature.State {
        var state = WindowManagerFeature.State()
        state.windows = windows.map { id, path in
            .init(id: id, window: .makeInitial(path: path))
        }
        state.focusedWindowID = focusedID
        return state
    }
}
