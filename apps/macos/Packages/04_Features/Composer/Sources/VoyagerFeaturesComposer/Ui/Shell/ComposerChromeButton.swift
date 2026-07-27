import SwiftUI
import VoyagerShared

struct ComposerChromeButton<Label: View>: View {
    let isEnabled: Bool
    let colorScheme: ColorScheme
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundColor(isEnabled ? .primary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipItem)
                        .fill(isEnabled && isHovering
                            ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme)
                            : .clear),
                )
        }
        .disabled(!isEnabled)
        .buttonStyle(.borderless)
        .onHover { isHovering = $0 }
    }
}
