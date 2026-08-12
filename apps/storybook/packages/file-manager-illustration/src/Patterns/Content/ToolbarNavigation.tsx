import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import { IconButton } from "../../UI/Controls/IconButton"

export const ToolbarNavigation: FC = () => (
  <div className="toolbar-left">
    <IconButton className="subtle" aria-label="Back">
      <SFSymbol name="chevron.left" size={13} weight={500} />
    </IconButton>
    <IconButton className="subtle" aria-label="Forward">
      <SFSymbol name="chevron.right" size={13} weight={500} />
    </IconButton>
    <IconButton className="subtle" aria-label="Go to Enclosing Folder">
      <SFSymbol name="chevron.up" size={13} weight={500} />
    </IconButton>
  </div>
)

ToolbarNavigation.displayName = "ToolbarNavigation"
