import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { ComposerPropertyPicker as ComposerPropertyPickerFixture } from "./composer-fixtures"

export type ComposerPropertyPickerProps = {
  readonly picker: ComposerPropertyPickerFixture
  readonly onSelect?: (key: string) => void
}

const categoryLabels = {
  common: "Common",
  date: "Date",
  filesystem: "Filesystem",
  misc: "Misc",
} as const

export const ComposerPropertyPicker: FC<ComposerPropertyPickerProps> = ({ picker, onSelect }) => {
  const recommended = picker.items.filter((item) => item.pinned)
  const categories = Object.entries(categoryLabels)
    .map(([key, label]) => ({
      key,
      label,
      items: picker.items.filter((item) => !item.pinned && item.category === key),
    }))
    .filter((group) => group.items.length > 0)

  const propertyRow = (item: (typeof picker.items)[number]) => (
    <button type="button" key={item.key} onClick={() => onSelect?.(item.key)}>
      <SFSymbol name={item.symbol} size={12} />
      {item.label}
    </button>
  )

  return (
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
        <small>Recommended</small>
        {recommended.map(propertyRow)}
        {categories.map((group) => (
          <div className="collection-composer-property-group" key={group.key}>
            <small>{group.label}</small>
            {group.items.map(propertyRow)}
          </div>
        ))}
      </div>
    </dialog>
  )
}

ComposerPropertyPicker.displayName = "ComposerPropertyPicker"
