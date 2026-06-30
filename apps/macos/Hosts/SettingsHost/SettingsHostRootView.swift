import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerPagesSettings

public struct SettingsHostRootView: View {
    public let store: StoreOf<SettingsHostFeature>

    public init(store: StoreOf<SettingsHostFeature>) {
        self.store = store
    }

    public var body: some View {
        SettingsView(store: store.scope(state: \.settings, action: \.settings))
            .frame(width: 600, height: 400)
    }
}
