import { useCallback, useEffect, useMemo, useReducer, useRef } from "react"
import type { FC } from "react"
import { FileBrowser } from "./Domains/Entries/FileBrowser"
import { FileManagerPrimaryContent } from "./Layouts/FileManagerPrimaryContent"
import { FileManagerWindowLayout } from "./Layouts/FileManagerWindowLayout"
import { InspectorPane } from "./Layouts/InspectorPane"
import { Sidebar } from "./Layouts/Sidebar"
import type { FileToolbarContent } from "./Patterns/Content/FileToolbar"
import { FileToolbar } from "./Patterns/Content/FileToolbar"
import { StatusBar } from "./Patterns/Content/StatusBar"
import { TrafficLights } from "./UI/Display/TrafficLights"
import {
  deriveBreadcrumbSegments,
  deriveSelectionLabel,
  propsToInitialParams,
} from "./lib/file-manager-adapter"
import { locationShortcuts } from "./lib/navigation-data"
import type { HomeFavorite, HomeLocation } from "./model/home"
import { createInitialState, getContentRoute, reducer } from "./model/reducer"
import type {
  EntrySelectionIntent,
  FileManagerIllustrationProps,
  SidebarTabItem,
} from "./model/types"
import "./styles/macos-tokens.css"
import "./styles/file-manager.css"
import "./styles/atoms.css"
import "./styles/form-controls.css"
import "./styles/menu-controls.css"
import "./styles/feedback.css"
import "./styles/overlays.css"
import "./styles/composer.css"
import "./styles/composer-overlays.css"
import "./styles/inspector.css"
import "./styles/sidebar.css"
import "./styles/window-shell.css"

export const FileManagerIllustration: FC<FileManagerIllustrationProps> = (props) => {
  const { files, contentContext, initialPresentation } = props
  const initial = propsToInitialParams(props)
  const [state, dispatch] = useReducer(reducer, initial, createInitialState)

  const prevFilesRef = useRef(files)
  const prevCtxRef = useRef(contentContext)
  const prevInitialPresentationRef = useRef(initialPresentation)

  useEffect(() => {
    if (
      prevFilesRef.current !== files ||
      prevCtxRef.current !== contentContext ||
      prevInitialPresentationRef.current !== initialPresentation
    ) {
      const resetData = propsToInitialParams({ files, contentContext, initialPresentation })
      dispatch({
        type: "RESET_DATA",
        ...resetData,
      })
      prevFilesRef.current = files
      prevCtxRef.current = contentContext
      prevInitialPresentationRef.current = initialPresentation
    }
  }, [files, contentContext, initialPresentation])

  const selectedEntries = useMemo(
    () => state.files.filter((e) => state.selectedEntryIds.includes(e.id)),
    [state.files, state.selectedEntryIds],
  )
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
    (entryId: string, intent: EntrySelectionIntent) =>
      dispatch({ type: "TOGGLE_ENTRY", entryId, intent }),
    [],
  )
  const handleClearSelection = useCallback(() => dispatch({ type: "SELECT_ENTRIES", ids: [] }), [])
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
  const handleNoop = useCallback(() => undefined, [])
  const handleChatErrorRecovery = props.chatOnErrorRecovery ?? handleNoop
  const handleChatRebindContext = props.chatOnRebindContext ?? handleNoop
  const handleChatStartNewChatFromRebind = props.chatOnStartNewChat ?? handleNoop

  const toolbarContent: FileToolbarContent = route.kind === "home" ? "home" : "directory"
  const controlledChat = props.chatSurface != null
  const effectiveInspectorOpen = controlledChat ? true : state.inspectorOpen
  const effectiveChatHeader = controlledChat
    ? props.chatSurface?.kind === "sessions"
      ? "sessions"
      : "chat"
    : state.inspectorChatHeader
  // native InspectorPaneView.chatHeaderTitle 과 대칭: sessions → "Chat History",
  // 그 외는 첫 사용자 메시지 접두(80자) → "New Chat".
  const chatSurfaceTitle = controlledChat ? deriveChatTitle(props.chatSurface) : null
  const inspectorChatTitle =
    effectiveChatHeader === "sessions" ? "Chat History" : (chatSurfaceTitle ?? windowTitle)
  const breadcrumbSegments = deriveBreadcrumbSegments(activeTab, selectedEntries)

  return (
    <div data-file-manager-illustration>
      <main className="stage">
        <section
          className={[
            "mac-window",
            !effectiveInspectorOpen && "inspector-closed",
            !state.sidebarOpen && "sidebar-closed",
          ]
            .filter(Boolean)
            .join(" ")}
          aria-label="Voyager File Manager"
        >
          <FileManagerWindowLayout
            sidebarOpen={state.sidebarOpen}
            inspectorOpen={effectiveInspectorOpen}
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
            breadcrumb={<StatusBar selectedLabel={selectedLabel} breadcrumb={breadcrumbSegments} />}
            content={
              <FileManagerPrimaryContent
                route={route}
                entries={state.files}
                selectedEntryIds={state.selectedEntryIds}
                viewMode={state.viewMode}
                onToggleEntry={handleToggleEntry}
                onClearSelection={handleClearSelection}
                onFavoriteSelect={handleHomeFavoriteSelect}
                onLocationSelect={handleHomeLocationSelect}
              />
            }
            inspector={
              <InspectorPane
                chatHeader={effectiveChatHeader}
                requestText={state.requestText}
                chatTitle={inspectorChatTitle}
                onRequestTextChange={handleRequestTextChange}
                onOpenChatHistory={handleOpenChatHistory}
                onOpenNewChat={handleOpenNewChat}
                onCloseChat={handleCloseChat}
                onSessionSelected={handleNoop}
                onOpenSettings={handleNoop}
                onErrorRecovery={handleChatErrorRecovery}
                onRegenerate={handleNoop}
                onRebindContext={handleChatRebindContext}
                onStartNewChatFromRebind={handleChatStartNewChatFromRebind}
                chatInputActions={props.chatInputActions}
                chatSurface={props.chatSurface}
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

function deriveChatTitle(state: FileManagerIllustrationProps["chatSurface"]): string | null {
  if (state == null || state.kind === "sessions") return null
  if (state.kind === "centeredEmpty") return "New Chat"
  const firstUser = state.messages?.find((message) => message.role === "user")
  if (firstUser == null) return "New Chat"
  const normalized = firstUser.content.split(/\s+/).join(" ").trim()
  return normalized.length > 0 ? normalized.slice(0, 80) : "New Chat"
}
