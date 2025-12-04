import ComposableArchitecture
import SwiftUI

struct InspectorPaneView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    store.send(.toggleInspector)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Spacer()
        }
        .frame(width: 300)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
