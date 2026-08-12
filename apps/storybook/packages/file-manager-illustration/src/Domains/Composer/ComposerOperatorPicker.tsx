import type { FC } from "react"
import type { ComposerOperatorPicker as ComposerOperatorPickerFixture } from "./composer-fixtures"

export type ComposerOperatorPickerProps = {
  readonly picker: ComposerOperatorPickerFixture
  readonly onSelect?: (code: string) => void
}

export const ComposerOperatorPicker: FC<ComposerOperatorPickerProps> = ({ picker, onSelect }) => (
  <dialog
    className="collection-composer-operator-picker"
    open
    aria-label="Condition operator picker"
  >
    <div className="collection-composer-picker-list">
      {picker.options.map((operator) => (
        <button type="button" key={operator.code} onClick={() => onSelect?.(operator.code)}>
          {operator.label}
        </button>
      ))}
    </div>
  </dialog>
)

ComposerOperatorPicker.displayName = "ComposerOperatorPicker"
