import type { FC } from "react"
import type { ContentRoute } from "../model/content-route"
import type { HomeFavorite, HomeLocation, HomeRecentChat } from "../model/home"
import type { Entry } from "../model/types"
import type { EntryViewMode } from "../molecules/FileToolbar"
import { AIChatWindow } from "../workflows/ai-chat/AIChatWindow"
import type { AiChatState } from "../workflows/ai-chat/types"
import { FileBrowser } from "./FileBrowser"
import { Home } from "./Home"

export interface FileManagerPrimaryContentProps {
  readonly route: ContentRoute
  readonly entries: readonly Entry[]
  readonly selectedEntryIds: readonly string[]
  readonly viewMode: EntryViewMode
  readonly aiChatState: AiChatState
  readonly onToggleEntry: (entryId: string, append: boolean) => void
  readonly onFavoriteSelect: (favorite: HomeFavorite) => void
  readonly onLocationSelect: (location: HomeLocation) => void
  readonly onRecentChatSelect: (chat: HomeRecentChat) => void
  readonly onStartPrimaryChat: () => void
}

function assertNeverRoute(route: never): never {
  throw new TypeError(`Unsupported File Manager route: ${JSON.stringify(route)}`)
}

export const FileManagerPrimaryContent: FC<FileManagerPrimaryContentProps> = ({
  route,
  entries,
  selectedEntryIds,
  viewMode,
  aiChatState,
  onToggleEntry,
  onFavoriteSelect,
  onLocationSelect,
  onRecentChatSelect,
  onStartPrimaryChat,
}) => {
  switch (route.kind) {
    case "home":
      return (
        <Home
          onFavoriteSelect={onFavoriteSelect}
          onLocationSelect={onLocationSelect}
          onRecentChatSelect={onRecentChatSelect}
          onNewChat={onStartPrimaryChat}
        />
      )
    case "ai-chat":
      return <AIChatWindow state={aiChatState} presentation="content" />
    case "browser":
      return (
        <FileBrowser
          entries={entries}
          selectedEntryIds={selectedEntryIds}
          viewMode={viewMode}
          onToggleEntry={onToggleEntry}
        />
      )
    default:
      return assertNeverRoute(route)
  }
}

FileManagerPrimaryContent.displayName = "FileManagerPrimaryContent"
