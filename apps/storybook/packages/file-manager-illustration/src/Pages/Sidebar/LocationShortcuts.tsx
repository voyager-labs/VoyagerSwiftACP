import { IconButton } from "@voyager-labs/design-foundation"
import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { LocationShortcutsProps } from "../../model/types"

const LOCATION_ICON_SIZE = 18

export const LocationShortcuts: FC<LocationShortcutsProps> = ({ shortcuts, onSelect }) => {
  return (
    <div className="location-shortcuts" aria-label="Location shortcuts">
      {shortcuts.map((shortcut) => (
        <IconButton
          key={shortcut.id}
          aria-label={shortcut.label}
          onClick={() => onSelect?.(shortcut)}
        >
          {shortcut.iconSrc ? (
            <img
              className="location-shortcut-icon"
              src={shortcut.iconSrc}
              alt=""
              width={LOCATION_ICON_SIZE}
              height={LOCATION_ICON_SIZE}
            />
          ) : (
            <SFSymbol name={shortcut.symbolName} size={LOCATION_ICON_SIZE} weight={500} />
          )}
        </IconButton>
      ))}
    </div>
  )
}

LocationShortcuts.displayName = "LocationShortcuts"
