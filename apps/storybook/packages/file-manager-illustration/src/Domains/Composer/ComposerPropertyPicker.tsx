import { type FC, useEffect, useRef, useState } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { ComposerPropertyOption } from "./composer-condition-options"
import type { ComposerPropertyPicker as ComposerPropertyPickerFixture } from "./composer-fixtures"

export type ComposerPropertyPickerProps = {
  readonly picker: ComposerPropertyPickerFixture
  readonly onSelect?: (key: string) => void
}

const categoryMeta = {
  common: { label: "Common", symbol: "square.grid.2x2" },
  date: { label: "Date", symbol: "calendar" },
  filesystem: { label: "Filesystem", symbol: "folder" },
  misc: { label: "Misc", symbol: "ellipsis.circle" },
} as const

type CategoryKey = keyof typeof categoryMeta

export const ComposerPropertyPicker: FC<ComposerPropertyPickerProps> = ({ picker, onSelect }) => {
  const [query, setQuery] = useState("")
  const [category, setCategory] = useState<CategoryKey | null>(null)
  const searchFieldRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    searchFieldRef.current?.focus()
  }, [])
  const search = query.trim().toLowerCase()

  const matches = (label: string) => search.length === 0 || label.toLowerCase().includes(search)

  const recommended = picker.items.filter((item) => item.pinned && matches(item.label))
  const categories = (Object.keys(categoryMeta) as readonly CategoryKey[])
    .map((key) => ({
      key,
      ...categoryMeta[key],
      items: picker.items.filter((item) => item.category === key && matches(item.label)),
    }))
    .filter((group) => group.items.length > 0)

  const hasResults = recommended.length > 0 || categories.length > 0
  // 네이티브는 category mode가 검색 결과와 무관하게 유지된다 (빈 결과 시 back + empty 표시)
  const categoryItems =
    category == null
      ? []
      : picker.items.filter((item) => item.category === category && matches(item.label))

  const propertyRow = (item: ComposerPropertyOption) => (
    <button type="button" key={item.key} onClick={() => onSelect?.(item.key)}>
      <SFSymbol name={item.symbol} size={12} />
      <span>{item.label}</span>
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
        <input
          ref={searchFieldRef}
          type="search"
          aria-label="Search attributes"
          placeholder="Search attributes"
          value={query}
          onChange={(event) => setQuery(event.currentTarget.value)}
        />
        {query.length > 0 && (
          <button
            type="button"
            className="collection-composer-picker-search-clear"
            aria-label="Clear search"
            onClick={() => setQuery("")}
          >
            <SFSymbol name="xmark.circle.fill" size={12} />
          </button>
        )}
      </div>
      {category != null ? (
        <div className="collection-composer-picker-list">
          <button
            type="button"
            className="collection-composer-picker-back"
            onClick={() => setCategory(null)}
          >
            <SFSymbol name="chevron.left" size={11} weight={600} />
            <span>{categoryMeta[category].label}</span>
          </button>
          {categoryItems.length > 0 ? (
            categoryItems.map(propertyRow)
          ) : (
            <div className="collection-composer-picker-empty">No properties found</div>
          )}
        </div>
      ) : search.length > 0 && !hasResults ? (
        <div className="collection-composer-picker-empty">No properties found</div>
      ) : (
        <div className="collection-composer-picker-list">
          {recommended.map(propertyRow)}
          {recommended.length > 0 && categories.length > 0 && (
            <div className="collection-composer-picker-separator" />
          )}
          {categories.map((group) => (
            <button
              type="button"
              className="collection-composer-category-row"
              key={group.key}
              onClick={() => setCategory(group.key)}
            >
              <SFSymbol name={group.symbol} size={12} />
              <span className="collection-composer-category-label">{group.label}</span>
              <small>{group.items.length}</small>
              <SFSymbol name="chevron.right" size={10} />
            </button>
          ))}
        </div>
      )}
    </dialog>
  )
}

ComposerPropertyPicker.displayName = "ComposerPropertyPicker"
