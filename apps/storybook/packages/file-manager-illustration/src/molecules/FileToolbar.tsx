import type { FC } from "react"
import { FileManagerIcon } from "../FileManagerIcon"
import { IconButton } from "../IconButton"

export type EntryViewMode = "grid" | "list"

export type FileToolbarContent = "directory" | "home" | "ai-chat"

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
        <IconButton aria-label="Back">
          <FileManagerIcon name="back" />
        </IconButton>
        <IconButton aria-label="Forward">
          <FileManagerIcon name="forward" />
        </IconButton>
        <IconButton aria-label="Parent">
          <FileManagerIcon name="parent" />
        </IconButton>
      </div>

      <div className="toolbar-title-area">
        <span className="toolbar-title-label">{title}</span>
        {content === "directory" && (
          <span className="toolbar-title-controls">
            <button
              className={`vc-icon-button${viewMode === "grid" ? " active" : ""}`}
              type="button"
              aria-label="Grid view"
              aria-pressed={viewMode === "grid"}
              onClick={() => onViewModeChange("grid")}
            >
              <FileManagerIcon name="grid" />
            </button>
            <button
              className={`vc-icon-button${viewMode === "list" ? " active" : ""}`}
              type="button"
              aria-label="List view"
              aria-pressed={viewMode === "list"}
              onClick={() => onViewModeChange("list")}
            >
              <FileManagerIcon name="list" />
            </button>
            <span className="toolbar-control-divider" />
            <button className="vc-icon-button" type="button" aria-label="Sort by name">
              <FileManagerIcon name="sort" />
            </button>
            <button className="vc-icon-button" type="button" aria-label="Group by kind">
              <FileManagerIcon name="group" />
            </button>
          </span>
        )}
      </div>

      <div className="toolbar-right">
        {content !== "ai-chat" && onNewChat && (
          <IconButton aria-label="New Chat" onClick={onNewChat}>
            <FileManagerIcon name="chat" />
          </IconButton>
        )}
        {showSidebarButton && (
          <IconButton aria-label="Show Sidebar" onClick={onToggleSidebar}>
            <FileManagerIcon name="sidebar" />
          </IconButton>
        )}
      </div>
    </header>
  )
}

FileToolbar.displayName = "FileToolbar"
