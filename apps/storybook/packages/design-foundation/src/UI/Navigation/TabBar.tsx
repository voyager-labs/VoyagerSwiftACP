import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import "../../styles/tab-bar.css"

/** 제품 비종속(native-style) 탭 바 아이템. id는 도메인에 묶이지 않는 문자열 키. */
export interface TabBarItem {
  readonly id: string
  readonly label: string
  /** SF Symbol 이름. */
  readonly icon: string
}

export interface TabBarProps {
  readonly items: readonly TabBarItem[]
  readonly activeId: string
  readonly onSelect: (id: string) => void
  /** <nav>의 aria-label. 기본값 "Tabs". */
  readonly ariaLabel?: string
}

/** macOS System Settings TabView idiom을 따르는 재사용 가능한 탭 바. */
export const TabBar: FC<TabBarProps> = ({ items, activeId, onSelect, ariaLabel = "Tabs" }) => {
  return (
    <nav className="tab-bar" aria-label={ariaLabel}>
      {items.map((item) => {
        const isActive = item.id === activeId
        return (
          <button
            key={item.id}
            type="button"
            className={`tab-bar-item${isActive ? " is-active" : ""}`}
            aria-current={isActive ? "page" : undefined}
            onClick={() => onSelect(item.id)}
          >
            <SFSymbol name={item.icon} size={16} weight={500} />
            <span className="tab-bar-label">{item.label}</span>
          </button>
        )
      })}
    </nav>
  )
}

TabBar.displayName = "TabBar"
