import ComposableArchitecture
import SwiftUI

struct ValuePickerView: View {
    let store: StoreOf<ValuePickerFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(alignment: .leading, spacing: 8) {
                if viewStore.valueArity == 0 {
                    Text("No value needed for this operator.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else if viewStore.valueArity == 1 {
                    valueField(
                        title: ValuePickerDisplayUtils.fieldTitle(for: viewStore.valueType),
                        placeholder: ValuePickerDisplayUtils.fieldPlaceholder(for: viewStore.valueType),
                        text: viewStore.binding(
                            get: { $0.values.first ?? "" },
                            send: { .setValue(index: 0, text: $0) },
                        ),
                    )
                } else {
                    ForEach(Array(viewStore.values.enumerated()), id: \.offset) { index, _ in
                        valueField(
                            title: ValuePickerDisplayUtils.fieldTitle(for: viewStore.valueType, index: index),
                            placeholder: ValuePickerDisplayUtils.fieldPlaceholder(for: viewStore.valueType),
                            text: viewStore.binding(
                                get: { $0.values.indices.contains(index) ? $0.values[index] : "" },
                                send: { .setValue(index: index, text: $0) },
                            ),
                        )
                    }
                }

                if let unitValueState = viewStore.unitValueState {
                    HStack {
                        Spacer()
                        UnitSelectorView(
                            availableUnitCodes: unitValueState.availableUnitCodes,
                            selectedUnitCode: unitValueState.selectedUnitCode,
                            selectedUnitLabel: UnitValuePresentationUtils.label(
                                for: unitValueState.selectedUnitCode,
                                state: unitValueState,
                            ),
                            labelForUnit: { UnitValuePresentationUtils.label(for: $0, state: unitValueState) },
                            onSelect: { viewStore.send(.selectUnit($0)) },
                        )
                    }
                }

                if let error = viewStore.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }

                HStack {
                    Spacer()
                    Button("Apply") {
                        viewStore.send(.commit)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
            .frame(width: 240)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(VoyagerDS.Surface.popoverBackground(for: colorScheme)),
            )
        })
    }

    private func valueField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }
}
