import ComposableArchitecture
import SwiftUI

struct ToolbarView: View {
    let store: StoreOf<FileManagerFeature>

    private let trafficLightAreaWidth: CGFloat = 80

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                if store.backHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(store.backHistory.enumerated().reversed()), id: \.offset) { index, path in
                        Button(
                            action: {
                                let originalIndex = store.backHistory.count - 1 - index
                                store.send(.goToHistoryIndex(originalIndex, isBackHistory: true))
                            },
                            label: {
                                Text(FileManager.default.displayName(atPath: path))
                            }
                        )
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(store.canGoBack ? .primary : .secondary)
            } primaryAction: {
                store.send(.goBack)
            }
            .menuIndicator(.hidden)
            .disabled(!store.canGoBack)
            .buttonStyle(.borderless)

            Menu {
                if store.forwardHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(store.forwardHistory.enumerated().reversed()), id: \.offset) { index, path in
                        Button(
                            action: {
                                let originalIndex = store.forwardHistory.count - 1 - index
                                store.send(.goToHistoryIndex(originalIndex, isBackHistory: false))
                            },
                            label: {
                                Text(FileManager.default.displayName(atPath: path))
                            }
                        )
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(store.canGoForward ? .primary : .secondary)
            } primaryAction: {
                store.send(.goForward)
            }
            .menuIndicator(.hidden)
            .disabled(!store.canGoForward)
            .buttonStyle(.borderless)

            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                Text(FileManager.default.displayName(atPath: store.currentPath))
                    .font(.system(size: 15, weight: .semibold))
            }

            Spacer()

            ToolbarMenuView(store: store)
        }
        .frame(maxHeight: .infinity)
        .padding(0)
        .padding(.leading, store.sidebarVisible ? 0 : trafficLightAreaWidth)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Color(red: 0.17, green: 0.17, blue: 0.17)

                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(height: 1.0)
                }
            }
        )
    }
}
