import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { ComposerPropertyPicker as ComposerPropertyPickerFixture } from "./composer-fixtures"

export type ComposerPropertyPickerProps = {
  readonly picker: ComposerPropertyPickerFixture
  readonly onSelect?: (key: string) => void
}

export const ComposerPropertyPicker: FC<ComposerPropertyPickerProps> = ({ picker, onSelect }) => (
  <dialog
    className="collection-composer-property-picker"
    open
    aria-label="Condition property picker"
  >
    <div className="collection-composer-picker-search">
      <SFSymbol name="magnifyingglass" size={12} />
      <span>Search attributes</span>
    </div>
    <div className="collection-composer-picker-list">
      {picker.items.map((item) => (
        <button type="button" key={item.key} onClick={() => onSelect?.(item.key)}>
          <SFSymbol name={item.symbol} size={12} />
          {item.label}
        </button>
      ))}
    </div>
  </dialog>
)

ComposerPropertyPicker.displayName = "ComposerPropertyPicker"
