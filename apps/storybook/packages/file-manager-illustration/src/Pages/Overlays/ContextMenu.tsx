import { Menu, MenuItem, MenuSeparator } from "@voyager-labs/design-foundation"
import type { FC } from "react"
import type { ContextMenuAction } from "../../model/types"

export interface ContextMenuProps {
  readonly actions: readonly ContextMenuAction[]
}

export const ContextMenu: FC<ContextMenuProps> = ({ actions }) => {
  return (
    <Menu className="fm-context-menu" aria-label="File context menu">
      {actions.map((action) =>
        action.separator ? (
          <MenuSeparator key={action.id} />
        ) : (
          <MenuItem
            key={action.id}
            label={action.label ?? ""}
            shortcut={action.shortcut}
            disabled={action.disabled}
          />
        ),
      )}
    </Menu>
  )
}

ContextMenu.displayName = "ContextMenu"
