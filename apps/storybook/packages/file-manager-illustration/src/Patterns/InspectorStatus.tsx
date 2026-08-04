import type { FC } from "react"
import { SFSymbol } from "../Foundations/SFSymbol"
import { IconButton } from "../UI/Controls/IconButton"

export const InspectorStatus: FC<Record<string, never>> = () => {
  return (
    <footer className="inspector-status">
      <span>● Chat Title</span>
      <div>
        <IconButton aria-label="Edit">
          <SFSymbol name="square.and.pencil" size={16} />
        </IconButton>
        <IconButton aria-label="Menu">
          <SFSymbol name="ellipsis" size={16} />
        </IconButton>
      </div>
    </footer>
  )
}

InspectorStatus.displayName = "InspectorStatus"
