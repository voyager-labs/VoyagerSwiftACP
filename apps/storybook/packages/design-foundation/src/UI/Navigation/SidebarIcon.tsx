import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { SidebarIconProps } from "../../model/ui-types"

/** SidebarIconKind → SF Symbol name 매핑 */
const SF_SYMBOL_MAP: Record<string, string> = {
  home: "house",
  collection: "rectangle.stack",
  chat: "bubble.right",
  folder: "folder",
  "folder-blue": "folder",
}

export const SidebarIcon: FC<SidebarIconProps> = ({ icon, isActive = false }) => {
  return (
    <span className={`nav-icon ${icon} ${isActive ? "active" : ""}`} aria-hidden="true">
      <SFSymbol name={SF_SYMBOL_MAP[icon] ?? "folder"} size={12} weight={600} />
    </span>
  )
}

SidebarIcon.displayName = "SidebarIcon"
