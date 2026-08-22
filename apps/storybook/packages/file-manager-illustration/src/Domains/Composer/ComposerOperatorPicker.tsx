import { Menu, MenuItem } from "@voyager-labs/design-foundation"
import type { FC } from "react"
import type { ComposerOperatorPicker as ComposerOperatorPickerFixture } from "./composer-fixtures"

export type ComposerOperatorPickerProps = {
  readonly picker: ComposerOperatorPickerFixture
  readonly onSelect?: (code: string) => void
}

export const ComposerOperatorPicker: FC<ComposerOperatorPickerProps> = ({ picker, onSelect }) => {
  return (
    <Menu
      className="collection-composer-operator-picker"
      aria-label="Condition operator picker"
      focusOnMount
    >
      {picker.options.map((operator) => (
        <MenuItem
          key={operator.code}
          role="menuitemradio"
          label={operator.label}
          checked={operator.code === picker.selectedCode}
          onClick={() => onSelect?.(operator.code)}
        />
      ))}
    </Menu>
  )
}

ComposerOperatorPicker.displayName = "ComposerOperatorPicker"
