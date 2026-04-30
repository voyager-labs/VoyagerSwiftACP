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
        WithViewStore(store, observe: \.notice) { viewStore in
            VStack(spacing: 0) {
                if let notice = viewStore.state {
                    noticeBanner(notice)
                }
                SettingsView(store: store.scope(state: \.settings, action: \.settings))
            }
            .frame(width: 600, height: 400)
        }
    }

    @ViewBuilder
    private func noticeBanner(_ notice: String) -> some View {
        HStack {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text(notice)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss") {
                store.send(.dismissNotice)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
