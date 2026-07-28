import { useCallback, useEffect, useMemo, useReducer, useRef } from "react"
import type { FC } from "react"
import { TrafficLights } from "./atoms/TrafficLights"
import { deriveBreadcrumb, deriveSelectionLabel, propsToInitialParams } from "./lib/file-manager-adapter"
import { locationShortcuts } from "./lib/navigation-data"
import type { HomeFavorite, HomeLocation } from "./model/home"
import { createInitialState, getContentRoute, reducer } from "./model/reducer"
import type { Entry, FileManagerIllustrationProps, SidebarTabItem } from "./model/types"
import type { FileToolbarContent } from "./molecules/FileToolbar"
import { FileToolbar } from "./molecules/FileToolbar"
import { StatusBar } from "./molecules/StatusBar"
import { FileBrowser } from "./organisms/FileBrowser"
import { FileManagerPrimaryContent } from "./organisms/FileManagerPrimaryContent"
import { FileManagerWindowLayout } from "./organisms/FileManagerWindowLayout"
import { InspectorPane } from "./organisms/InspectorPane"
import { Sidebar } from "./organisms/Sidebar"
import "./styles/macos-tokens.css"
import "./styles/file-manager.css"
import "./styles/atoms.css"
import "./styles/inspector.css"
import "./styles/sidebar.css"
import "./styles/window-shell.css"

export const FileManagerIllustration: FC<FileManagerIllustrationProps> = (props) => {
  const { files, contentContext } = props
  const initial = propsToInitialParams(props)
  const [state, dispatch] = useReducer(reducer, initial, createInitialState)

  const prevFilesRef = useRef(files)
  const prevCtxRef = useRef(contentContext)

  useEffect(() => {
    if (prevFilesRef.current !== files || prevCtxRef.current !== contentContext) {
      const resetData = propsToInitialParams({ files, contentContext })
      dispatch({
        type: "RESET_DATA",
        ...resetData,
      })
      prevFilesRef.current = files
      prevCtxRef.current = contentContext
    }
  }, [files, contentContext])

  const selectedEntries = useMemo(
    () => state.files.filter((e) => state.selectedEntryIds.includes(e.id)),
    [state.files, state.selectedEntryIds],
  )
  const primaryEntry: Entry | null = selectedEntries[0] ?? state.files[0] ?? null
  const activeTab = useMemo(
    () => state.tabs.find((t) => t.id === state.activeTabId) ?? null,
    [state.tabs, state.activeTabId],
  )
  const windowTitle = activeTab?.label ?? "Untitled"
  const route = getContentRoute(state)
  const selectedLabel = deriveSelectionLabel(selectedEntries.length, state.files.length)

  const sidebarPinnedTabs = useMemo(
    () =>
      state.tabs
        .filter((t) => t.isPinned)
        .map((t) => ({ ...t, active: t.id === state.activeTabId })),
    [state.tabs, state.activeTabId],
  )
  const sidebarContentTabs = useMemo(
    () =>
      state.tabs
        .filter((t) => !t.isPinned)
        .map((t) => ({ ...t, active: t.id === state.activeTabId })),
    [state.tabs, state.activeTabId],
  )

  const handleToggleEntry = useCallback(
    (entryId: string, append: boolean) => dispatch({ type: "TOGGLE_ENTRY", entryId, append }),
    [],
  )
  const handleViewModeChange = useCallback(
    (mode: "grid" | "list") => dispatch({ type: "SET_VIEW_MODE", mode }),
    [],
  )
  const handleToggleSidebar = useCallback(() => dispatch({ type: "TOGGLE_SIDEBAR" }), [])
  const handleRequestTextChange = useCallback(
    (text: string) => dispatch({ type: "SET_REQUEST_TEXT", text }),
    [],
  )
  const handleSidebarTabSelect = useCallback(
    (item: SidebarTabItem) => dispatch({ type: "SELECT_TAB", item }),
    [],
  )
  const handleSidebarLocationSelect = useCallback(
    () => dispatch({ type: "RESTORE_CONTENT_TAB", destinationTabId: "directory" }),
    [],
  )
  const handleTabUnpin = useCallback(
    (item: SidebarTabItem) => dispatch({ type: "UNPIN_TAB", item }),
    [],
  )
  const handleTabClose = useCallback(
    (item: SidebarTabItem) => dispatch({ type: "CLOSE_TAB", item }),
    [],
  )
  const handleNewTab = useCallback(() => dispatch({ type: "NEW_TAB" }), [])

  const handleHomeFavoriteSelect = useCallback(
    (favorite: HomeFavorite) =>
      dispatch({
        type: "RESTORE_CONTENT_TAB",
        destinationTabId: favorite.destinationTabId,
        pageAnchor: favorite.pageAnchor,
        secondary: favorite.pageAnchor,
      }),
    [],
  )
  const handleHomeLocationSelect = useCallback(
    (location: HomeLocation) =>
      dispatch({
        type: "RESTORE_CONTENT_TAB",
        destinationTabId: location.destinationTabId,
        pageAnchor: location.path,
      }),
    [],
  )
  const handleOpenContextualChat = useCallback(() => dispatch({ type: "OPEN_NEW_CHAT" }), [])
  const handleOpenChatHistory = useCallback(() => dispatch({ type: "OPEN_CHAT_HISTORY" }), [])
  const handleOpenNewChat = useCallback(() => dispatch({ type: "OPEN_NEW_CHAT" }), [])
  const handleCloseChat = useCallback(() => dispatch({ type: "CLOSE_CHAT" }), [])

  const toolbarContent: FileToolbarContent = route.kind === "home" ? "home" : "directory"
  const inspectorChatTitle = state.inspectorChatHeader === "sessions" ? "Chat History" : windowTitle
  const breadcrumbText = deriveBreadcrumb(route, activeTab)

  return (
    <div data-file-manager-illustration>
      <main className="stage">
        <section
          className={[
            "mac-window",
            !state.inspectorOpen && "inspector-closed",
            !state.sidebarOpen && "sidebar-closed",
          ]
            .filter(Boolean)
            .join(" ")}
          aria-label="Voyager File Manager"
        >
          <FileManagerWindowLayout
            sidebarOpen={state.sidebarOpen}
            inspectorOpen={state.inspectorOpen}
            sidebar={
              <Sidebar
                locationShortcuts={locationShortcuts}
                pinnedTabs={sidebarPinnedTabs}
                contentTabs={sidebarContentTabs}
                onLocationSelect={handleSidebarLocationSelect}
                onTabSelect={handleSidebarTabSelect}
                onTabUnpin={handleTabUnpin}
                onTabClose={handleTabClose}
                onNewTab={handleNewTab}
                onToggleSidebar={handleToggleSidebar}
              />
            }
            toolbar={
              <FileToolbar
                title={windowTitle}
                content={toolbarContent}
                viewMode={state.viewMode}
                showSidebarButton={!state.sidebarOpen}
                onViewModeChange={handleViewModeChange}
                onToggleSidebar={handleToggleSidebar}
                onNewChat={handleOpenContextualChat}
              />
            }
            breadcrumb={<StatusBar selectedLabel={selectedLabel} breadcrumb={breadcrumbText} />}
            content={
              <FileManagerPrimaryContent
                route={route}
                entries={state.files}
                selectedEntryIds={state.selectedEntryIds}
                viewMode={state.viewMode}
                onToggleEntry={handleToggleEntry}
                onFavoriteSelect={handleHomeFavoriteSelect}
                onLocationSelect={handleHomeLocationSelect}
              />
            }
            inspector={
              <InspectorPane
                chatHeader={state.inspectorChatHeader}
                requestText={state.requestText}
                selectedEntries={selectedEntries}
                primaryEntry={primaryEntry}
                chatTitle={inspectorChatTitle}
                onRequestTextChange={handleRequestTextChange}
                onOpenChatHistory={handleOpenChatHistory}
                onOpenNewChat={handleOpenNewChat}
                onCloseChat={handleCloseChat}
              />
            }
          />
          <div className="mac-titlebar-controls" aria-hidden="true">
            <TrafficLights />
          </div>
        </section>
      </main>
    </div>
  )
}

FileManagerIllustration.displayName = "FileManagerIllustration"
