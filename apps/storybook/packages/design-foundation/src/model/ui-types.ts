/* Design Foundation UI kit 공용 타입 — Sidebar/Navigation/Display 컴포넌트.
 *
 * file-manager-illustration의 model/types.ts에서 끌어온 것으로,
 * fmi의 도메인 소비자 호환을 위해 동일 구조로 유지한다.
 */

export type SidebarIconKind = "home" | "folder" | "folder-blue" | "collection" | "chat"

/** 내부 breadcrumb 세그먼트 — SF Symbol 이름으로 아이콘 렌더링. */
export type BreadcrumbSegment = {
  readonly label: string
  readonly symbolName: string
}

export type SidebarTabItem = {
  readonly id: string
  readonly label: string
  readonly icon: SidebarIconKind
  readonly active?: boolean
  readonly isPinned?: boolean
  readonly secondary?: string
  readonly pageAnchor?: string
  readonly breadcrumb?: readonly BreadcrumbSegment[]
}

export type SidebarTabAction = (item: SidebarTabItem) => void

export type SidebarIconProps = {
  readonly icon: SidebarIconKind
  readonly isActive?: boolean
}

export type SidebarNavItemProps = {
  readonly item: SidebarTabItem
  readonly actionRevealed?: boolean
  readonly onSelect?: SidebarTabAction
  readonly onUnpin?: SidebarTabAction
  readonly onClose?: SidebarTabAction
}

export type TrafficLightsProps = Record<string, never>
