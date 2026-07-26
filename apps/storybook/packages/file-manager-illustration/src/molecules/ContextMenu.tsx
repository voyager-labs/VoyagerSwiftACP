import type { FC } from "react"
import type { ContextMenuAction } from "../types"

export interface ContextMenuProps {
  readonly actions: readonly ContextMenuAction[]
}

export const ContextMenu: FC<ContextMenuProps> = ({ actions }) => {
  return (
    <div className="fm-context-menu" role="menu" aria-label="File context menu">
      {actions.map((action) => (
        <button
          key={action.id}
          type="button"
          role="menuitem"
          disabled={action.disabled}
          className={action.destructive ? "destructive" : undefined}
        >
          <span>{action.label}</span>
          {action.shortcut ? <kbd>{action.shortcut}</kbd> : null}
        </button>
      ))}
    </div>
  )
}

ContextMenu.displayName = "ContextMenu"
