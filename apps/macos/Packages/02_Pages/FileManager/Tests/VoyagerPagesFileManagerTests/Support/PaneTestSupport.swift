import ComposableArchitecture
import Foundation
@testable import VoyagerPagesFileManager
import XCTest

// FileManagerSidebarPreferenceReducer의 클램프 상수와 동기화된 패인 테스트 서포트.

@MainActor
enum PaneTestSupport {
    enum SidebarWidth {
        static let min: CGFloat = 150
        static let max: CGFloat = 400
        static let defaultValue: CGFloat = 220
        static let inRange: CGFloat = 250
        static let belowMinimum: CGFloat = 100
        static let aboveMaximum: CGFloat = 500
    }

    static func makeSidebarStore(
        initialState: FileManagerSidebarState = FileManagerSidebarState(),
    ) -> TestStore<FileManagerSidebarState, FileManagerSidebarAction> {
        TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
        }
    }

    static func makeInspectorStore(
        initialState: FileManagerInspectorState = FileManagerInspectorState(),
    ) -> TestStore<FileManagerInspectorState, FileManagerInspectorAction> {
        TestStore(initialState: initialState) {
            FileManagerInspectorFeature()
        }
    }

    static func makeSidebarState(
        visible: Bool = true,
        width: CGFloat = SidebarWidth.defaultValue,
    ) -> FileManagerSidebarState {
        var state = FileManagerSidebarState()
        state.sidebarVisible = visible
        state.sidebarWidth = width
        return state
    }

    static func makeInspectorState(
        visible: Bool = false,
        paneExists: Bool = false,
    ) -> FileManagerInspectorState {
        var state = FileManagerInspectorState()
        state.inspectorVisible = visible
        state.inspectorPaneExists = paneExists
        return state
    }
}
