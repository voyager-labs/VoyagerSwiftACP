import type { FC } from "react"
import { FileBrowser } from "../Domains/Entries/FileBrowser"
import type { EntryViewMode } from "../Patterns/Content/FileToolbar"
import type { ContentRoute } from "../model/content-route"
import type { HomeFavorite, HomeLocation } from "../model/home"
import type { Entry } from "../model/types"
import { Home } from "./Home"

export interface FileManagerPrimaryContentProps {
  readonly route: ContentRoute
  readonly entries: readonly Entry[]
  readonly selectedEntryIds: readonly string[]
  readonly viewMode: EntryViewMode
  readonly onToggleEntry: (entryId: string, append: boolean) => void
  readonly onFavoriteSelect: (favorite: HomeFavorite) => void
  readonly onLocationSelect: (location: HomeLocation) => void
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
  onFavoriteSelect,
  onLocationSelect,
}) => {
  switch (route.kind) {
    case "home":
      return <Home onFavoriteSelect={onFavoriteSelect} onLocationSelect={onLocationSelect} />
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
