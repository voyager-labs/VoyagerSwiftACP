import type { FC } from "react"
import { IconButton } from "../atoms/IconButton"
import type { LocationShortcutsProps } from "../model/types"

export const LocationShortcuts: FC<LocationShortcutsProps> = ({ shortcuts, onSelect }) => {
  return (
    <div className="location-shortcuts" aria-label="Location shortcuts">
      {shortcuts.map((shortcut) => (
        <IconButton
          key={shortcut.id}
          aria-label={shortcut.label}
          onClick={() => onSelect?.(shortcut)}
        >
          {shortcut.glyph}
        </IconButton>
      ))}
    </div>
  )
}

LocationShortcuts.displayName = "LocationShortcuts"
