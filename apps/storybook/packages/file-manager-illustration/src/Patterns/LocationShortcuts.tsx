import type { FC } from "react"
import { SFSymbol } from "../Foundations/SFSymbol"
import { IconButton } from "../UI/Controls/IconButton"
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
          <SFSymbol name={shortcut.symbolName} size={16} />
        </IconButton>
      ))}
    </div>
  )
}

LocationShortcuts.displayName = "LocationShortcuts"
