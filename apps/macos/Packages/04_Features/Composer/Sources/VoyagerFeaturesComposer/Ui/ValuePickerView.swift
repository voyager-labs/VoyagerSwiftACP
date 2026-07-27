import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerShared

struct ValuePickerView: View {
    let store: StoreOf<ValuePickerFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            let valueInputCount = requiredValueInputCount(
                contract: viewStore.valueContract,
                currentValues: viewStore.values,
            )
            let propertyType = viewStore.condition?.property.type.rawValue ?? "string"
            VStack(alignment: .leading, spacing: 8) {
                if valueInputCount == 0 {
                    Text("No value needed for this operator.")
                        .font(VoyagerDS.Typography.caption)
                        .foregroundColor(.secondary)
                } else if valueInputCount == 1 {
                    valueField(
                        title: ConditionValueFieldPresentation.fieldTitle(for: propertyType),
                        placeholder: ConditionValueFieldPresentation.fieldPlaceholder(for: propertyType),
                        text: viewStore.binding(
                            get: { $0.values.first ?? "" },
                            send: { .setValue(index: 0, text: $0) },
                        ),
                    )
                } else {
                    ForEach(Array(viewStore.values.enumerated()), id: \.offset) { index, _ in
                        valueField(
                            title: ConditionValueFieldPresentation.fieldTitle(for: propertyType, index: index),
                            placeholder: ConditionValueFieldPresentation.fieldPlaceholder(for: propertyType),
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
                            selectedUnitLabel: unitValueState.label(for: unitValueState.selectedUnitCode),
                            labelForUnit: { unitValueState.label(for: $0) },
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
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.control)
                    .fill(VoyagerDS.Surface.popoverBackground(for: colorScheme)),
            )
        })
    }

    private func valueField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(VoyagerDS.Typography.chip)
                .foregroundColor(.secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(VoyagerDS.Typography.caption)
        }
    }

    private func requiredValueInputCount(
        contract: Condition.ValueContract?,
        currentValues: [String],
    ) -> Int {
        switch contract?.count {
        case let .fixed(count):
            count
        case .multiple:
            max(currentValues.count, 1)
        case nil:
            0
        }
    }
}
