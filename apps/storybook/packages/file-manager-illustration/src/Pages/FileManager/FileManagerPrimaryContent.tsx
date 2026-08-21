import type { FC } from "react"
import type { ContentRoute } from "../../model/content-route"
import type { HomeChat, HomeFavorite, HomeLocation } from "../../model/home"
import type { EntryViewMode } from "../../model/types"
import type { Entry, EntrySelectionIntent } from "../../model/types"
import { Home } from "../Home/Home"
import { FileBrowser } from "./FileBrowser"

export interface FileManagerPrimaryContentProps {
  readonly route: ContentRoute
  readonly entries: readonly Entry[]
  readonly selectedEntryIds: readonly string[]
  readonly viewMode: EntryViewMode
  readonly onToggleEntry: (entryId: string, intent: EntrySelectionIntent) => void
  readonly onClearSelection?: () => void
  readonly onFavoriteSelect: (favorite: HomeFavorite) => void
  readonly onLocationSelect: (location: HomeLocation) => void
  readonly onNewChat?: () => void
  readonly onChatSelect?: (chat: HomeChat) => void
}

function assertNeverRoute(route: never): never {
  throw new TypeError(`Unsupported File Manager route: ${JSON.stringify(route)}`)
}

export const FileManagerPrimaryContent: FC<FileManagerPrimaryContentProps> = ({
  route,
  entries,
  selectedEntryIds,
  viewMode,
  onToggleEntry,
  onClearSelection,
  onFavoriteSelect,
  onLocationSelect,
  onNewChat,
  onChatSelect,
}) => {
  switch (route.kind) {
    case "home":
      return (
        <Home
          onFavoriteSelect={onFavoriteSelect}
          onLocationSelect={onLocationSelect}
          onNewChat={onNewChat}
          onChatSelect={onChatSelect}
        />
      )
    case "browser":
      return (
        <FileBrowser
          entries={entries}
          selectedEntryIds={selectedEntryIds}
          viewMode={viewMode}
          onToggleEntry={onToggleEntry}
          onClearSelection={onClearSelection}
        />
      )
    default:
      return assertNeverRoute(route)
  }
}

FileManagerPrimaryContent.displayName = "FileManagerPrimaryContent"
