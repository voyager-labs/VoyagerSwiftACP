import type { ContentRoute } from "../model/content-route"
import type {
  ContentTab,
  Entry,
  FileEntry,
  FileManagerIllustrationProps,
  SidebarTabItem,
} from "../model/types"
import type { ChatMessage } from "../model/types"
import type { AiChatState } from "../workflows/ai-chat/types"

/** Convert public FileEntry to internal Entry. */
export function toEntry(f: FileEntry): Entry {
  return {
    id: f.id,
    name: f.displayName,
    kind: f.kind,
    meta: f.secondaryLabel ?? f.extension ?? undefined,
  }
}

/** Convert public ContentTab to SidebarTabItem with sensible defaults. */
export function toSidebarTabItem(tab: ContentTab): SidebarTabItem {
  const icon = tab.id === "home" ? "home" : tab.id === "ai-chat" ? "chat" : "folder-blue"
  const isPinned = ["recents", "downloads", "desktop", "documents", "projects"].includes(tab.id)
  return { id: tab.id, label: tab.label, icon, isPinned }
}

/** Convert public props to reducer initial params. */
export function propsToInitialParams(props: FileManagerIllustrationProps): {
  files: readonly Entry[]
  chatMessages: readonly ChatMessage[]
  tabs: readonly SidebarTabItem[]
  activeTabId: string | null
} {
  return {
    files: props.files.map(toEntry),
    chatMessages: props.chatMessages,
    tabs: props.contentContext.tabs.map(toSidebarTabItem),
    activeTabId: props.contentContext.activeTabId,
  }
}

/** Build a minimal AiChatState from public chat messages. */
export function buildAiChatState(messages: readonly ChatMessage[]): AiChatState {
  return {
    mode: "chat",
    executionPhase: "idle",
    modelState: "loaded",
    selectedModel: "GPT-5.2",
    sessions: [],
    selectedSessionId: undefined,
    contextSummary: "Collection context",
    contextCount: messages.length,
    draftText: "",
    messages: messages.map((message, index) => ({
      id: `msg-${index}`,
      author: message.role,
      text: message.paragraph,
      meta: message.role === "user" ? "You" : "Voyager AI",
    })),
    attachments: [],
  }
}

/** Derive breadcrumb text from route. */
export function deriveBreadcrumb(route: ContentRoute, activeTab: SidebarTabItem | null): string {
  if (route.kind === "browser") {
    const segments = route.pageAnchor?.split("/").filter((segment) => segment.length > 0)
    return segments && segments.length > 0
      ? segments.join(" / ")
      : (activeTab?.label ?? "Directory")
  }
  return ""
}

/** Derive selection status label. */
export function deriveSelectionLabel(selectedCount: number, totalCount: number): string {
  if (selectedCount === 0) return `${totalCount} items`
  return `${selectedCount} of ${totalCount} selected`
}
