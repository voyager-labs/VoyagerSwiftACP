import type { FC } from "react"
import { IconButton } from "../ui/controls/IconButton"

export const InspectorStatus: FC<Record<string, never>> = () => {
  return (
    <footer className="inspector-status">
      <span>● Chat Title</span>
      <div>
        <IconButton aria-label="Edit">□</IconButton>
        <IconButton aria-label="Menu">≡</IconButton>
      </div>
    </footer>
  )
}

InspectorStatus.displayName = "InspectorStatus"
