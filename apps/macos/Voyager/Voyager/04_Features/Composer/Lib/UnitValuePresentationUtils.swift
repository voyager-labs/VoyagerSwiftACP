import Foundation

enum UnitValuePresentationUtils {
    static func makeState(
        spec: UnitValueUtils.UnitSpec,
        preferredUnitCode: String? = nil,
    ) -> UnitValueState {
        let availableUnitCodes = UnitValueUtils.unitCodes(spec: spec)
        let selectedUnitCode = preferredUnitCode
            .flatMap { availableUnitCodes.contains($0) ? $0 : nil }
            ?? UnitValueUtils.defaultDisplayUnitCode(spec: spec)
        let unitLabelsByCode = Dictionary(uniqueKeysWithValues: availableUnitCodes.map {
            ($0, UnitValueUtils.unitLabel(for: $0, spec: spec))
        })
        return UnitValueState(
            selectedUnitCode: selectedUnitCode,
            availableUnitCodes: availableUnitCodes,
            unitLabelsByCode: unitLabelsByCode,
        )
    }

    static func label(for code: String, state: UnitValueState) -> String {
        state.unitLabelsByCode[code] ?? code
    }
}
