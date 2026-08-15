import { type FC, useEffect, useRef } from "react"
import type { ComposerOperatorPicker as ComposerOperatorPickerFixture } from "./composer-fixtures"

export type ComposerOperatorPickerProps = {
  readonly picker: ComposerOperatorPickerFixture
  readonly onSelect?: (code: string) => void
}

export const ComposerOperatorPicker: FC<ComposerOperatorPickerProps> = ({ picker, onSelect }) => {
  const selectedOptionRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    selectedOptionRef.current?.focus()
  }, [])

  return (
    <dialog
      className="collection-composer-operator-picker"
      open
      aria-label="Condition operator picker"
    >
      <div className="collection-composer-picker-list">
        {picker.options.map((operator, index) => (
          <button
            type="button"
            ref={
              operator.code === picker.selectedCode || (picker.selectedCode === "" && index === 0)
                ? selectedOptionRef
                : undefined
            }
            key={operator.code}
            aria-pressed={operator.code === picker.selectedCode}
            onClick={() => onSelect?.(operator.code)}
          >
            {operator.label}
          </button>
        ))}
      </div>
    </dialog>
  )
}

ComposerOperatorPicker.displayName = "ComposerOperatorPicker"
