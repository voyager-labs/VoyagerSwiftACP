import ComposableArchitecture
import SwiftUI

struct OperatorPickerView: View {
    let store: StoreOf<OperatorPickerFeature>
    @Environment(\.colorScheme)
    private var colorScheme
    @State private var hoveredOptionCode: String?

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewStore.options, id: \.self) { code in
                            Button {
                                viewStore.send(.select(code))
                            } label: {
                                let isHovering = hoveredOptionCode == code
                                let label = viewStore.optionLabels[code] ?? code
                                HStack {
                                    Text(label)
                                        .foregroundColor(.primary)
                                        .font(.system(size: 12))
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isHovering ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear),
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredOptionCode = hovering ? code : nil
                            }
                        }
                    }
                }
            }
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(VoyagerDS.Surface.popoverBackground(for: colorScheme)),
            )
        })
    }
}
