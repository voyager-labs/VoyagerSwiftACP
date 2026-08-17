import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { SidebarNavItemProps } from "../../model/ui-types"
import { SidebarIcon } from "./SidebarIcon"

export const SidebarNavItem: FC<SidebarNavItemProps> = ({
  item,
  actionRevealed = false,
  onSelect,
  onUnpin,
  onClose,
}) => {
  function handleAction() {
    if (item.isPinned) {
      onUnpin?.(item)
      return
    }
    onClose?.(item)
  }

  const containerClass = ["nav-item-container", actionRevealed ? "action-revealed" : ""]
    .filter(Boolean)
    .join(" ")

  return (
    <div className={containerClass}>
      <button
        className={["nav-item", item.active ? "active" : ""].filter(Boolean).join(" ")}
        type="button"
        aria-current={item.active ? "page" : undefined}
        onClick={() => onSelect?.(item)}
      >
        <SidebarIcon icon={item.icon} isActive={item.active ?? false} />
        <strong>{item.secondary ?? item.label}</strong>
      </button>
      <button
        className="nav-item-action"
        type="button"
        aria-label={item.isPinned ? `Unpin ${item.label}` : `Close ${item.label}`}
        onClick={handleAction}
      >
        <SFSymbol name={item.isPinned ? "minus" : "xmark"} size={10} weight={500} />
      </button>
    </div>
  )
}

SidebarNavItem.displayName = "SidebarNavItem"
