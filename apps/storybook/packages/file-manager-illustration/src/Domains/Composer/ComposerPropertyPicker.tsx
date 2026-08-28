import { Menu, MenuSeparator } from "@voyager-labs/design-foundation"
import { type FC, useEffect, useRef, useState } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { ComposerPropertyOption } from "./composer-condition-options"
import type { ComposerPropertyPicker as ComposerPropertyPickerFixture } from "./composer-fixtures"

export type ComposerPropertyPickerProps = {
  readonly picker: ComposerPropertyPickerFixture
  readonly onSelect?: (key: string) => void
}

// 네이티브 ConditionPropertyIcon.iconName(forCategory:) 매핑
const categoryMeta = {
  audio: { label: "Audio", symbol: "speaker.wave.2" },
  common: { label: "Common", symbol: "list.bullet.rectangle" },
  date: { label: "Date", symbol: "calendar" },
  filesystem: { label: "Filesystem", symbol: "folder" },
  image: { label: "Image", symbol: "photo" },
  misc: { label: "Misc", symbol: "questionmark.circle" },
  video: { label: "Video", symbol: "video" },
} as const

type CategoryKey = keyof typeof categoryMeta

export const ComposerPropertyPicker: FC<ComposerPropertyPickerProps> = ({ picker, onSelect }) => {
  const [query, setQuery] = useState("")
  const [openCategory, setOpenCategory] = useState<CategoryKey | null>(null)
  // 네이티브 NSMenu는 서브메뉴 상단을 부모 행에 맞춘다: 클릭 시 행 오프셋을 기록한다
  const [submenuOrigin, setSubmenuOrigin] = useState<{ top: number; left: number }>({
    top: 0,
    left: 0,
  })
  const searchFieldRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    searchFieldRef.current?.focus()
  }, [])

  // 네이티브는 검색 변경 시 메뉴 전체를 재구성하므로 열려 있던 서브메뉴는 함께 닫는다
  const handleSearchChange = (value: string) => {
    setQuery(value)
    setOpenCategory(null)
  }

  const search = query.trim().toLowerCase()

  // 네이티브 filteredProperties: 이미 사용 중인 property는 숨기되 편집 대상은 예외
  const available = picker.items.filter(
    (item) =>
      picker.editingKey === item.key ||
      !(picker.existingKeys ?? []).some((key) => key === item.key),
  )
  const filtered =
    search.length === 0
      ? available
      : available.filter((item) => item.label.toLowerCase().includes(search))
  const recommended = filtered.filter((item) => item.pinned)
  const recommendedKeys = new Set(recommended.map((item) => item.key))
  // 네이티브 groupedByCategory: recommended는 카테고리에서 제외하고, 빈 카테고리는 drop, 키 정렬 순서
  const categories = (Object.keys(categoryMeta) as CategoryKey[])
    .sort()
    .map((key) => ({
      key,
      ...categoryMeta[key],
      items: filtered.filter((item) => item.category === key && !recommendedKeys.has(item.key)),
    }))
    .filter((group) => group.items.length > 0)

  const openGroup = categories.find((group) => group.key === openCategory)

  // 서브메뉴를 닫을 때 포커스를 돌려줄 부모 카테고리 행
  const lastCategoryRowRef = useRef<HTMLButtonElement>(null)

  const toggleGroup = (key: CategoryKey, row: HTMLButtonElement) => {
    if (openCategory === key) {
      setOpenCategory(null)
      return
    }
    lastCategoryRowRef.current = row
    const groupEl = row.closest(".collection-composer-property-picker-group")
    const menuEl = groupEl?.querySelector<HTMLElement>(".collection-composer-property-picker")
    if (menuEl != null) {
      const rowRect = row.getBoundingClientRect()
      const menuRect = menuEl.getBoundingClientRect()
      // 보이는 행 위치 기준 배치(offsetTop은 스크롤 전 콘텐츠 좌표라 사용 불가)
      const desired = rowRect.top - menuRect.top
      // ponytail: 320은 .collection-composer-property-submenu max-height와 짝이 맞는 상수, CSS 변경 시 함께 조정
      const submenuMaxHeight = 320
      const overflowBelow = menuRect.top + desired + submenuMaxHeight - window.innerHeight
      const clamped = overflowBelow > 0 ? Math.max(0, desired - overflowBelow) : desired
      setSubmenuOrigin({ top: clamped, left: menuRect.width })
    }
    setOpenCategory(key)
  }

  const propertyRow = (item: ComposerPropertyOption) => (
    <button
      type="button"
      role="menuitemradio"
      key={item.key}
      className="fm-menu-item"
      aria-checked={picker.selectedKey === item.key}
      onClick={() => onSelect?.(item.key)}
    >
      {picker.selectedKey === item.key && (
        <span className="fm-menu-item-checkmark" aria-hidden="true">
          {"\u2713"}
        </span>
      )}
      <SFSymbol name={item.symbol} size={14} />
      <span className="fm-menu-item-label">{item.label}</span>
    </button>
  )

  return (
    <div className="collection-composer-property-picker-group">
      <Menu className="collection-composer-property-picker" aria-label="Condition property picker">
        {/* 네이티브 ComposerNativeMenuSearchRow: 아이콘·클리어 없는 캐럿 전용 검색 행 */}
        <div className="collection-composer-picker-search">
          <input
            ref={searchFieldRef}
            type="search"
            aria-label="Search attributes"
            placeholder="Search attributes"
            value={query}
            onChange={(event) => handleSearchChange(event.currentTarget.value)}
          />
        </div>
        <MenuSeparator />
        {filtered.length === 0 ? (
          // 네이티브 빈 결과: magnifyingglass 이미지를 가진 비활성 행 하나
          <button type="button" role="menuitem" className="fm-menu-item" disabled>
            <SFSymbol name="magnifyingglass" size={14} />
            <span className="fm-menu-item-label">No properties found</span>
          </button>
        ) : (
          <div className="collection-composer-property-list">
            {recommended.length > 0 && (
              <>
                <div className="collection-composer-picker-caption">Recommended</div>
                {recommended.map(propertyRow)}
              </>
            )}
            {categories.length > 0 && (
              <>
                {recommended.length > 0 && <MenuSeparator />}
                <div className="collection-composer-picker-caption">Categories</div>
                {categories.map((group) => (
                  <button
                    type="button"
                    role="menuitem"
                    key={group.key}
                    className="fm-menu-item"
                    aria-haspopup="menu"
                    aria-expanded={openCategory === group.key}
                    onClick={(event) => toggleGroup(group.key, event.currentTarget)}
                    onKeyDown={(event) => {
                      // 네이티브 NSMenu 계약: ArrowRight로 서브메뉴에 진입한다
                      if (event.key === "ArrowRight" && openCategory !== group.key) {
                        event.preventDefault()
                        toggleGroup(group.key, event.currentTarget)
                      }
                    }}
                  >
                    <SFSymbol name={group.symbol} size={14} />
                    <span className="fm-menu-item-label">{group.label}</span>
                    <SFSymbol name="chevron.right" size={12} />
                  </button>
                ))}
              </>
            )}
          </div>
        )}
      </Menu>
      {/* 네이티브 submenu 번역: 루트 메뉴를 유지한 채 부모 행 높이에 인접 배치한다 */}
      {openGroup != null && (
        <Menu
          key={openGroup.key}
          className="collection-composer-property-submenu"
          aria-label={`${openGroup.label} properties`}
          focusOnMount
          onKeyDown={(event) => {
            // 네이티브 NSMenu 계약: ArrowLeft·Escape로 부모 행에 포커스를 복원하며 닫는다
            if (event.key === "ArrowLeft" || event.key === "Escape") {
              event.preventDefault()
              event.stopPropagation()
              setOpenCategory(null)
              lastCategoryRowRef.current?.focus()
            }
          }}
          style={{ top: submenuOrigin.top, left: submenuOrigin.left }}
        >
          {openGroup.items.map(propertyRow)}
        </Menu>
      )}
    </div>
  )
}

ComposerPropertyPicker.displayName = "ComposerPropertyPicker"
