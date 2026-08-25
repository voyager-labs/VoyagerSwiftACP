import { SidebarNavItem } from "@voyager-labs/design-foundation"
import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { LocationShortcut, SidebarTabAction, SidebarTabItem } from "../../model/types"
import { LocationShortcuts } from "./LocationShortcuts"

export interface SidebarProps {
  readonly locationShortcuts: readonly LocationShortcut[]
  readonly pinnedTabs: readonly SidebarTabItem[]
  readonly contentTabs: readonly SidebarTabItem[]
  readonly revealTabActions?: boolean
  readonly standalone?: boolean
  readonly onLocationSelect?: (location: LocationShortcut) => void
  readonly onTabSelect?: SidebarTabAction
  readonly onTabUnpin?: SidebarTabAction
  readonly onTabClose?: SidebarTabAction
  readonly onNewTab?: () => void
}

export const Sidebar: FC<SidebarProps> = ({
  locationShortcuts,
  pinnedTabs,
  contentTabs,
  revealTabActions = false,
  standalone = false,
  onLocationSelect,
  onTabSelect,
  onTabUnpin,
  onTabClose,
  onNewTab,
}) => {
  const classes = ["sidebar", standalone ? "standalone" : ""].filter(Boolean).join(" ")

  return (
    <aside className={classes} aria-label="Sidebar">
      <div className="sidebar-titlebar" aria-hidden="true" />

      {/* Fixed locations grid — outside scroll area (native: .padding(.top, 50)) */}
      <LocationShortcuts shortcuts={locationShortcuts} onSelect={onLocationSelect} />

      {/* Scrollable tab area */}
      <nav className="sidebar-tab-list" aria-label="Content tabs">
        {pinnedTabs.map((item) => (
          <SidebarNavItem
            key={item.id}
            item={item}
            actionRevealed={revealTabActions}
            onSelect={onTabSelect}
            onUnpin={onTabUnpin}
          />
        ))}
        {pinnedTabs.length > 0 && <div className="sidebar-divider" />}
        {contentTabs.map((item) => (
          <SidebarNavItem
            key={item.id}
            item={item}
            actionRevealed={revealTabActions || !!item.active}
            onSelect={onTabSelect}
            onClose={onTabClose}
          />
        ))}
        {(pinnedTabs.length > 0 || contentTabs.length > 0) && (
          <button
            className="sidebar-new-tab"
            type="button"
            aria-label="Create new tab"
            onClick={onNewTab}
          >
            <SFSymbol name="plus" size={16} />
            <span>New Tab</span>
          </button>
        )}
      </nav>
    </aside>
  )
}

Sidebar.displayName = "Sidebar"
