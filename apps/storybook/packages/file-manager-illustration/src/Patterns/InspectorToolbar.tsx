import type { FC } from "react"
import { SFSymbol } from "../Foundations/SFSymbol"
import { IconButton } from "../UI/Controls/IconButton"
import { SegmentedControl } from "../UI/Navigation/SegmentedControl"

export type InspectorMode = "chat" | "properties" | "preview"

export interface InspectorToolbarProps {
  mode: InspectorMode
  onModeChange: (mode: InspectorMode) => void
}

const modeSegments = [
  { value: "chat", label: "●" },
  { value: "properties", label: "⌁" },
] as const

export const InspectorToolbar: FC<InspectorToolbarProps> = ({ mode, onModeChange }) => {
  return (
    <header className="inspector-toolbar">
      <SegmentedControl
        options={modeSegments}
        value={mode}
        onChange={(v) => onModeChange(v as InspectorMode)}
      />
      <div className="pane-actions">
        <IconButton aria-label="More">
          <SFSymbol name="ellipsis" size={16} />
        </IconButton>
        <IconButton aria-label="Layout">
          <SFSymbol name="rectangle.3.group" size={16} />
        </IconButton>
      </div>
    </header>
  )
}

InspectorToolbar.displayName = "InspectorToolbar"
