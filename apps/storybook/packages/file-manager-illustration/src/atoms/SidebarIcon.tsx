import type { FC } from "react"
import { SFSymbol } from "../foundations/SFSymbol"
import type { SidebarIconProps } from "../model/types"

/** SidebarIconKind → SF Symbol name 매핑 */
const SF_SYMBOL_MAP: Record<string, string> = {
  home: "house",
  collection: "rectangle.stack",
  chat: "bubble.right",
  folder: "folder",
  "folder-blue": "folder",
}

export const SidebarIcon: FC<SidebarIconProps> = ({ icon }) => {
  return (
    <span className={`nav-icon ${icon}`} aria-hidden="true">
      <SFSymbol name={SF_SYMBOL_MAP[icon] ?? "folder"} size={18} />
    </span>
  )
}

SidebarIcon.displayName = "SidebarIcon"
