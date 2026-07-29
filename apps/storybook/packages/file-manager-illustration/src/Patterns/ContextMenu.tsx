import type { FC } from "react"
import { MenuItem } from "../UI/Controls/MenuItem"
import type { ContextMenuAction } from "../model/types"

export interface ContextMenuProps {
  readonly actions: readonly ContextMenuAction[]
}

export const ContextMenu: FC<ContextMenuProps> = ({ actions }) => {
  return (
    <div className="fm-context-menu" role="menu" aria-label="File context menu">
      {actions.map((action) => (
        <MenuItem
          key={action.id}
          label={action.label}
          shortcut={action.shortcut}
          destructive={action.destructive}
          disabled={action.disabled}
        />
      ))}
    </div>
  )
}

ContextMenu.displayName = "ContextMenu"
