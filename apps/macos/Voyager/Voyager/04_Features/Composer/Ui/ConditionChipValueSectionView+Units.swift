import ComposableArchitecture
import SwiftUI

extension ConditionChipValueSectionView {
    @ViewBuilder
    func displayRangeUnitSelector() -> some View {
        if let selector = displayUnitSelector(
            unitValueState: currentUnitValueState(),
            onSelect: { unitCode in
                onDisplayUnitChange(condition.propertyKey, unitCode)
            },
        ) {
            selector
        }
    }

    func editUnitSelector(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> AnyView? {
        guard let unitValueState = valueViewStore.unitValueState,
              condition.valueType == "number"
        else {
            return nil
        }

        return AnyView(
            UnitSelectorView(
                availableUnitCodes: unitValueState.availableUnitCodes,
                selectedUnitCode: unitValueState.selectedUnitCode,
                selectedUnitLabel: UnitValuePresentationUtils.label(
                    for: unitValueState.selectedUnitCode,
                    state: unitValueState,
                ),
                labelForUnit: { UnitValuePresentationUtils.label(for: $0, state: unitValueState) },
                onSelect: { valuePickerStore.send(.selectUnit($0)) },
            ),
        )
    }

    func displayUnitSelector(
        unitValueState: UnitValueState?,
        onSelect: @escaping (String) -> Void,
    ) -> AnyView? {
        guard let unitValueState else {
            return nil
        }

        return AnyView(
            UnitSelectorView(
                availableUnitCodes: unitValueState.availableUnitCodes,
                selectedUnitCode: unitValueState.selectedUnitCode,
                selectedUnitLabel: UnitValuePresentationUtils.label(
                    for: unitValueState.selectedUnitCode,
                    state: unitValueState,
                ),
                labelForUnit: { UnitValuePresentationUtils.label(for: $0, state: unitValueState) },
                onSelect: onSelect,
            ),
        )
    }

    func updateInlineValueFocus(shouldFocus: Bool, targetIndex: Int?) {
        let nextFocus = shouldFocus ? targetIndex : nil
        guard focusedValueIndex != nextFocus else { return }
        DispatchQueue.main.async {
            focusedValueIndex = nextFocus
        }
    }
}
