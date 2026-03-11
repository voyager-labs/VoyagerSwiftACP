import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerShared

@Reducer
struct FileManagerFeature {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Scope(state: \.content, action: \.content) {
            FileManagerContentFeature()
        }

        Scope(state: \.sidebar, action: \.sidebar) {
            FileManagerSidebarFeature()
        }

        Scope(state: \.inspector, action: \.inspector) {
            FileManagerInspectorFeature()
        }

        FileManagerWindowNavigationReducer()
        FileManagerWindowOrchestrationReducer()
    }
}
