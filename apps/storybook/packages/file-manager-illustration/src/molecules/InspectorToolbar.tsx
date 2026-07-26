import type { FC } from "react"
import { IconButton } from "../IconButton"
import { SegmentedControl } from "../SegmentedControl"

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
        <IconButton aria-label="More">•••</IconButton>
        <IconButton aria-label="Layout">▣</IconButton>
      </div>
    </header>
  )
}

InspectorToolbar.displayName = "InspectorToolbar"
