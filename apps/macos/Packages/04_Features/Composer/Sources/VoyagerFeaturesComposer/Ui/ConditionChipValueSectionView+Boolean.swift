import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerShared

private struct ConditionChipBooleanButtonLabelView: View {
    let currentText: String
    let placeholderText: String
    let isHovering: Bool
    let isDark: Bool
    let hoverFillOpacity: Double

    var body: some View {
        Text(labelText)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(currentText.isEmpty ? .secondary : .primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: 50, maxWidth: 70, alignment: .center)
            .fixedSize(horizontal: true, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isHovering
                            ? (isDark ? Color.white.opacity(hoverFillOpacity) : Color.black.opacity(hoverFillOpacity))
                            : Color.white.opacity(0.0001),
                    ),
            )
    }

    private var labelText: String {
        currentText.isEmpty
            ? (placeholderText.isEmpty ? "Value" : placeholderText.capitalized)
            : currentText.capitalized
    }
}

extension ConditionChipValueSectionView {
    func booleanValueButton(
        placeholderText: String,
        currentText: String,
        index: Int,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
        operatorCode: String,
        valueUIKind: String,
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { boolPopoverIndex == index },
            set: { show in
                if !show { boolPopoverIndex = nil }
            },
        )
        let isHovering = boolHoverIndex == index

        return Button {
            sendPrepare(
                operatorCode: operatorCode,
                valueUIKind: valueUIKind,
                valueArity: 1,
                editingIndex: index,
                existingValues: condition.values,
                includeDisplayState: false,
                valueType: "boolean",
            )
            boolPopoverIndex = index
        } label: {
            ConditionChipBooleanButtonLabelView(
                currentText: currentText,
                placeholderText: placeholderText,
                isHovering: isHovering,
                isDark: isDark,
                hoverFillOpacity: hoverFillOpacity,
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hover in
            if hover {
                boolHoverIndex = index
            } else if boolHoverIndex == index {
                boolHoverIndex = nil
            }
        }
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            booleanPopoverContent(valueViewStore: valueViewStore)
        }
    }

    func booleanPopoverContent(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            booleanOption("True", valueViewStore: valueViewStore)
            booleanOption("False", valueViewStore: valueViewStore)
        }
        .padding(10)
        .frame(width: 150)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(VoyagerDS.Surface.popoverBackground(for: isDark ? .dark : .light)),
        )
    }

    func booleanOption(
        _ title: String,
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        booleanOptionButton(title, isHovering: boolOptionHoverValue == title) {
            valueViewStore.send(.setValue(index: 0, text: title))
            valuePickerStore.send(.commit)
            boolPopoverIndex = nil
        }
        .onHover { hovering in
            boolOptionHoverValue = hovering ? title : (boolOptionHoverValue == title ? nil : boolOptionHoverValue)
        }
    }

    func booleanOptionButton(_ title: String, isHovering: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isHovering
                            ? (isDark ? Color.white.opacity(hoverFillOpacity) : Color.black.opacity(hoverFillOpacity))
                            : Color.clear,
                    ),
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
