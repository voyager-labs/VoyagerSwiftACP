import { contentTabs } from "../lib/navigation-data"
import type { ContentRoute } from "./content-route"
import { deriveContentRoute } from "./content-route"
import type { Entry, SidebarTabItem } from "./types"

export interface State {
  readonly tabs: readonly SidebarTabItem[]
  readonly activeTabId: string | null
  readonly files: readonly Entry[]
  readonly selectedEntryIds: readonly string[]
  readonly viewMode: "grid" | "list"
  readonly sidebarOpen: boolean
  readonly inspectorOpen: boolean
  /** Chat-only inspector header state: sessions list or active conversation. */
  readonly inspectorChatHeader: "sessions" | "chat"
  readonly requestText: string
  readonly previousActiveTabId: string | null
  readonly nextHomeTabNumber: number
}

export type Action =
  | { readonly type: "SELECT_ENTRIES"; readonly ids: readonly string[] }
  | { readonly type: "TOGGLE_ENTRY"; readonly entryId: string; readonly append: boolean }
  | { readonly type: "SET_VIEW_MODE"; readonly mode: "grid" | "list" }
  | { readonly type: "TOGGLE_SIDEBAR" }
  | { readonly type: "SET_REQUEST_TEXT"; readonly text: string }
  | { readonly type: "SELECT_TAB"; readonly item: SidebarTabItem }
  | { readonly type: "CLOSE_TAB"; readonly item: SidebarTabItem }
  | { readonly type: "UNPIN_TAB"; readonly item: SidebarTabItem }
  | { readonly type: "NEW_TAB" }
  | {
      readonly type: "RESTORE_CONTENT_TAB"
      readonly destinationTabId: "directory" | "collection"
      readonly secondary?: string
      readonly pageAnchor?: string
    }
  | {
      readonly type: "RESET_DATA"
      readonly files: readonly Entry[]
      readonly tabs: readonly SidebarTabItem[]
      readonly activeTabId: string | null
    }
  /* Inspector chat header actions */
  | { readonly type: "OPEN_CHAT_HISTORY" }
  | { readonly type: "OPEN_NEW_CHAT" }
  | { readonly type: "CLOSE_CHAT" }

export interface InitialStateParams {
  readonly files: readonly Entry[]
  readonly tabs: readonly SidebarTabItem[]
  readonly activeTabId: string | null
}

export function createInitialState(params: InitialStateParams): State {
  return {
    tabs: params.tabs.map((t) => ({ ...t })),
    activeTabId: params.activeTabId,
    files: params.files,
    selectedEntryIds: [],
    viewMode: "grid",
    sidebarOpen: true,
    inspectorOpen: false,
    inspectorChatHeader: "sessions",
    requestText: "",
    previousActiveTabId: null,
    nextHomeTabNumber: 1,
  }
}

/** Derive ContentRoute from current state using the active tab item. */
export function getContentRoute(state: State): ContentRoute {
  const activeTab = state.tabs.find((t) => t.id === state.activeTabId) ?? null
  return deriveContentRoute(activeTab)
}

/** Activate a tab — reused by SELECT_TAB, CLOSE_TAB, RESTORE_CONTENT_TAB. */
function activateTab(
  state: State,
  tab: SidebarTabItem,
  previousActiveTabId: string | null,
  extras: Partial<State> = {},
): State {
  if (tab.id === "home" || tab.icon === "home") {
    return {
      ...state,
      ...extras,
      previousActiveTabId,
      activeTabId: tab.id,
      inspectorOpen: false,
    }
  }
  return {
    ...state,
    ...extras,
    previousActiveTabId,
    activeTabId: tab.id,
    inspectorOpen: false,
  }
}

export function reducer(state: State, action: Action): State {
  switch (action.type) {
    case "SELECT_ENTRIES":
      return { ...state, selectedEntryIds: action.ids }
    case "TOGGLE_ENTRY": {
      const { entryId, append } = action
      if (append) {
        return {
          ...state,
          selectedEntryIds: state.selectedEntryIds.includes(entryId)
            ? state.selectedEntryIds.filter((id) => id !== entryId)
            : [...state.selectedEntryIds, entryId],
        }
      }
      return { ...state, selectedEntryIds: [entryId] }
    }
    case "SET_VIEW_MODE":
      return { ...state, viewMode: action.mode }
    case "TOGGLE_SIDEBAR":
      return { ...state, sidebarOpen: !state.sidebarOpen }
    case "SET_REQUEST_TEXT":
      return { ...state, requestText: action.text }
    case "SELECT_TAB": {
      const { item } = action
      const prev = item.id !== state.activeTabId ? state.activeTabId : state.previousActiveTabId
      return activateTab(state, item, prev)
    }
    case "CLOSE_TAB": {
      const { item } = action
      const remainingTabs = state.tabs.filter((t) => t.id !== item.id)
      const isActiveTab = item.id === state.activeTabId
      const prev = state.previousActiveTabId === item.id ? null : state.previousActiveTabId
      if (!isActiveTab) return { ...state, tabs: remainingTabs, previousActiveTabId: prev }
      const closedIndex = state.tabs.findIndex((t) => t.id === item.id)
      const previousTab = prev ? remainingTabs.find((t) => t.id === prev) : undefined
      const neighborTab =
        closedIndex === -1
          ? undefined
          : (remainingTabs[closedIndex] ?? remainingTabs[closedIndex - 1])
      const fallbackTab =
        previousTab ?? neighborTab ?? remainingTabs.find((t) => t.id === "home") ?? remainingTabs[0]
      if (!fallbackTab) {
        return {
          ...state,
          tabs: remainingTabs,
          activeTabId: null,
          previousActiveTabId: null,
          inspectorOpen: false,
        }
      }
      return activateTab(state, fallbackTab, null, { tabs: remainingTabs })
    }
    case "UNPIN_TAB": {
      const unpinned = state.tabs.find((t) => t.id === action.item.id)
      if (!unpinned) return state
      return {
        ...state,
        tabs: [
          ...state.tabs.filter((t) => t.id !== action.item.id),
          { ...unpinned, isPinned: false },
        ],
      }
    }
    case "NEW_TAB": {
      const number = state.nextHomeTabNumber
      const newTab: SidebarTabItem = {
        id: `home-tab-${number}`,
        label: `Untitled ${number}`,
        icon: "home",
      }
      return {
        ...state,
        tabs: [...state.tabs, newTab],
        nextHomeTabNumber: number + 1,
        activeTabId: newTab.id,
        previousActiveTabId: state.activeTabId,
        inspectorOpen: false,
      }
    }
    case "RESTORE_CONTENT_TAB": {
      const { destinationTabId, secondary, pageAnchor } = action
      const existingTab = state.tabs.find((t) => t.id === destinationTabId)
      if (existingTab) {
        const updatedTab = {
          ...existingTab,
          secondary: secondary ?? existingTab.secondary,
          pageAnchor: pageAnchor ?? existingTab.pageAnchor,
        }
        const tabs = state.tabs.map((t) => (t.id === destinationTabId ? updatedTab : t))
        return activateTab(state, updatedTab, state.activeTabId, { tabs })
      }
      const templateTab = contentTabs.find((t) => t.id === destinationTabId)
      if (!templateTab) return state
      const restoredTab = { ...templateTab, active: false, secondary, pageAnchor }
      return activateTab(state, restoredTab, state.activeTabId, {
        tabs: [...state.tabs, restoredTab],
      })
    }
    case "RESET_DATA":
      return {
        ...state,
        files: action.files,
        tabs: action.tabs.map((t) => ({ ...t })),
        activeTabId: action.activeTabId,
        inspectorOpen: false,
        inspectorChatHeader: "sessions",
      }
    case "OPEN_CHAT_HISTORY":
      return { ...state, inspectorChatHeader: "sessions" }
    case "OPEN_NEW_CHAT":
      return { ...state, inspectorOpen: true, inspectorChatHeader: "chat" }
    case "CLOSE_CHAT":
      return { ...state, inspectorOpen: false }
  }
}
