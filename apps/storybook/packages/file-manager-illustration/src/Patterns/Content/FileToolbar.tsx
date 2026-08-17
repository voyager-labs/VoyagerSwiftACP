import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import { IconButton } from "../../UI/Controls/IconButton"

export type EntryViewMode = "grid" | "list"

export type FileToolbarContent = "directory" | "home"

export interface FileToolbarProps {
  /** Active tab title (e.g. "Directory", "Home", "Ask Voyager"). */
  title: string
  /** Content kind — determines which controls are visible. */
  content: FileToolbarContent
  viewMode: EntryViewMode
  /** True when sidebar is closed — show the "Show Sidebar" button. */
  showSidebarButton: boolean
  onViewModeChange: (mode: EntryViewMode) => void
  onToggleSidebar: () => void
  onNewChat?: () => void
}

export const FileToolbar: FC<FileToolbarProps> = ({
  title,
  content,
  viewMode,
  showSidebarButton,
  onViewModeChange,
  onToggleSidebar,
  onNewChat,
}) => {
  return (
    <header className="toolbar">
      <div className="toolbar-left">
        <IconButton className="subtle" aria-label="Back">
          <SFSymbol name="chevron.left" size={13} weight={500} />
        </IconButton>
        <IconButton className="subtle" aria-label="Forward">
          <SFSymbol name="chevron.right" size={13} weight={500} />
        </IconButton>
        <IconButton className="subtle" aria-label="Parent">
          <SFSymbol name="chevron.up" size={13} weight={500} />
        </IconButton>
      </div>

      <div className="toolbar-title-area">
        <span className="toolbar-title-content">
          <SFSymbol name="folder" size={12} weight={300} />
          <span className="toolbar-title-label">{title}</span>
        </span>
        {content === "directory" && (
          <span className="toolbar-title-controls">
            <IconButton
              aria-label={viewMode === "grid" ? "Grid view" : "List view"}
              className="subtle"
              onClick={() => onViewModeChange(viewMode === "grid" ? "list" : "grid")}
            >
              <SFSymbol
                name={viewMode === "grid" ? "square.grid.2x2" : "list.bullet"}
                size={13}
                weight={500}
              />
            </IconButton>
            <IconButton className="subtle" aria-label="Sort and group">
              <SFSymbol name="arrow.up.arrow.down" size={13} weight={500} />
            </IconButton>
          </span>
        )}
      </div>

      <div className="toolbar-right">
        {onNewChat && (
          <IconButton className="subtle" aria-label="New Chat" onClick={onNewChat}>
            <SFSymbol name="sidebar.trailing" size={13} weight={500} />
          </IconButton>
        )}
        {showSidebarButton && (
          <IconButton className="subtle" aria-label="Show Sidebar" onClick={onToggleSidebar}>
            <SFSymbol name="sidebar.left" size={13} weight={500} />
          </IconButton>
        )}
      </div>
    </header>
  )
}

FileToolbar.displayName = "FileToolbar"
