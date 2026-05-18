import SwiftUI

struct UnitSelectorView: View {
    let availableUnitCodes: [String]
    let selectedUnitCode: String
    let selectedUnitLabel: String
    let labelForUnit: (String) -> String
    let onSelect: (String) -> Void

    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 4
    var cornerRadius: CGFloat = 4
    var strokeColor: Color = .secondary.opacity(0.25)

    var body: some View {
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
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(strokeColor, lineWidth: 1),
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
