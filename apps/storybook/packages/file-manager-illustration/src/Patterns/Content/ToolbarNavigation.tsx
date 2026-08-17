import { IconButton } from "@voyager-labs/design-foundation"
import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"

export const ToolbarNavigation: FC = () => (
  <div className="toolbar-left">
    <IconButton className="subtle" aria-label="Back" disabled>
      <SFSymbol name="chevron.left" size={13} weight={500} />
    </IconButton>
    <IconButton className="subtle" aria-label="Forward" disabled>
      <SFSymbol name="chevron.right" size={13} weight={500} />
    </IconButton>
    <IconButton className="subtle" aria-label="Go to Enclosing Folder" disabled>
      <SFSymbol name="chevron.up" size={13} weight={500} />
    </IconButton>
  </div>
)

ToolbarNavigation.displayName = "ToolbarNavigation"
