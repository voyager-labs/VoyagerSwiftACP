import SwiftUI
import VoyagerShared

struct UnitSelectorView: View {
    let availableUnitCodes: [String]
    let selectedUnitCode: String
    let selectedUnitLabel: String
    let labelForUnit: (String) -> String
    let onSelect: (String) -> Void

    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 4
    var cornerRadius: CGFloat = VoyagerDS.Radius.chipItem

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        Group {
            if ComposerPickerHostPolicy.host(for: .unit) == .nativeMenu {
                Menu {
                    ForEach(availableUnitCodes, id: \.self) { unitCode in
                        Button {
                            onSelect(unitCode)
                        } label: {
                            let label = labelForUnit(unitCode)
                            if unitCode == selectedUnitCode {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                } label: {
                    Text(selectedUnitLabel)
                        .font(VoyagerDS.Typography.chip)
                        .foregroundColor(.primary)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(VoyagerDS.Surface.chipItemBorder(for: colorScheme), lineWidth: 1),
                        )
                }
                .menuStyle(.borderlessButton)
                .disabled(availableUnitCodes.isEmpty)
                .fixedSize()
            }
        }
    }
}
