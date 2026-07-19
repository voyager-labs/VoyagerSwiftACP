import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection

extension ConditionChipValueSectionView {
    func editUnitSelector(
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> AnyView? {
        guard let state = valueStore.unitValueState else { return nil }
        return AnyView(unitSelector(state: state) {
            valuePickerStore.send(.selectUnit($0))
        })
    }

    func displayUnitSelector(unitValueState: UnitValueState?) -> AnyView? {
        guard let state = unitValueState else { return nil }
        return AnyView(unitSelector(state: state) {
            store.send(.view(.setDisplayUnit($0)))
        })
    }

    private func unitSelector(
        state: UnitValueState,
        onSelect: @escaping (String) -> Void,
    ) -> UnitSelectorView {
        UnitSelectorView(
            availableUnitCodes: state.availableUnitCodes,
            selectedUnitCode: state.selectedUnitCode,
            selectedUnitLabel: state.label(for: state.selectedUnitCode),
            labelForUnit: { state.label(for: $0) },
            onSelect: onSelect,
        )
    }

    func updateInlineValueFocus(shouldFocus: Bool, targetIndex: Int?) {
        let nextFocus = shouldFocus ? targetIndex : nil
        guard focusedValueIndex != nextFocus else { return }
        DispatchQueue.main.async { focusedValueIndex = nextFocus }
    }
}
