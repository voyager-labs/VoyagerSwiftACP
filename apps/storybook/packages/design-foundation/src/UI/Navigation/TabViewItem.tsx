import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { TabItem } from "./TabView"
import "../../styles/tab-view.css"

export interface TabViewItemProps {
  readonly item: TabItem
  readonly isActive: boolean
  readonly onSelect: () => void
}

/**
 * 독립적인 TabView 아이템 컴포넌트. SwiftUI TabView의 각 탭 / AppKit NSTabViewItem에 대응한다.
 * 아이콘(위) + 라벨(아래)의 세로 배치로 하나의 탭을 렌더링한다.
 */
export const TabViewItem: FC<TabViewItemProps> = ({ item, isActive, onSelect }) => {
  return (
    <button
      type="button"
      className={`tab-view-item${isActive ? " is-active" : ""}`}
      aria-current={isActive ? "page" : undefined}
      onClick={onSelect}
    >
      <SFSymbol name={item.icon} size={20} weight={500} />
      <span className="tab-view-item-label">{item.label}</span>
    </button>
  )
}

TabViewItem.displayName = "TabViewItem"
