import type { ButtonHTMLAttributes, FC } from "react"

export interface MenuItemProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  label: string
  shortcut?: string
  detail?: string
  checked?: boolean
}

const SHORTCUT_MODIFIERS = new Set(["⌘", "⇧", "⌥", "⌃"])

function splitShortcut(shortcut: string): { modifiers: string; key: string } {
  let end = 0
  for (const ch of shortcut) {
    if (SHORTCUT_MODIFIERS.has(ch)) end += ch.length
    else break
  }
  return { modifiers: shortcut.slice(0, end), key: shortcut.slice(end) }
}

export const MenuItem: FC<MenuItemProps> = ({
  label,
  shortcut,
  detail,
  checked,
  className = "",
  role = "menuitem",
  ...props
}) => {
  const classes = ["fm-menu-item", className].filter(Boolean).join(" ")
  const { modifiers, key } = shortcut ? splitShortcut(shortcut) : { modifiers: "", key: "" }

  return (
    <button
      type="button"
      role={role}
      className={classes}
      aria-checked={role === "menuitemradio" ? checked : undefined}
      {...props}
    >
      {checked ? (
        <span className="fm-menu-item-checkmark" aria-hidden="true">
          {"\u2713"}
        </span>
      ) : null}
      <span className="fm-menu-item-label">{label}</span>
      {detail ? <span className="fm-menu-item-detail">{detail}</span> : null}
      {shortcut ? (
        <kbd>
          {modifiers ? <span className="fm-menu-item-shortcut-modifiers">{modifiers}</span> : null}
          {key ? <span className="fm-menu-item-shortcut-key">{key}</span> : null}
        </kbd>
      ) : null}
    </button>
  )
}

MenuItem.displayName = "MenuItem"
