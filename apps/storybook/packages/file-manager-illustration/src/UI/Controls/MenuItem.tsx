import type { ButtonHTMLAttributes, FC } from "react"

export interface MenuItemProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  label: string
  shortcut?: string
  destructive?: boolean
}

export const MenuItem: FC<MenuItemProps> = ({
  label,
  shortcut,
  destructive,
  className = "",
  ...props
}) => {
  const classes = ["fm-menu-item", destructive ? "destructive" : "", className]
    .filter(Boolean)
    .join(" ")

  return (
    <button type="button" role="menuitem" className={classes} {...props}>
      <span>{label}</span>
      {shortcut ? <kbd>{shortcut}</kbd> : null}
    </button>
  )
}

MenuItem.displayName = "MenuItem"
