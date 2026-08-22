import type { FC } from "react"
import { TabViewItem } from "./TabViewItem"
import "../../styles/tab-view.css"

/** 제품 비종속(native-style) TabView 아이템. id는 도메인에 묶이지 않는 문자열 키. */
export interface TabItem {
  readonly id: string
  readonly label: string
  /** SF Symbol 이름. */
  readonly icon: string
}

export interface TabViewProps {
  readonly items: readonly TabItem[]
  readonly activeId: string
  readonly onSelect: (id: string) => void
  /** <nav>의 aria-label. 기본값 "Navigation". */
  readonly ariaLabel?: string
}

/**
 * macOS TabView idiom을 따르는 재사용 가능한 가로 탭 바.
 * 항목들은 좌→우 가로로 배치되고, 각 항목은 아이콘(위) + 라벨(아래)의 세로 구조다.
 */
export const TabView: FC<TabViewProps> = ({
  items,
  activeId,
  onSelect,
  ariaLabel = "Navigation",
}) => {
  return (
    <nav className="tab-view" aria-label={ariaLabel}>
      {items.map((item) => (
        <TabViewItem
          key={item.id}
          item={item}
          isActive={item.id === activeId}
          onSelect={() => onSelect(item.id)}
        />
      ))}
    </nav>
  )
}

TabView.displayName = "TabView"
