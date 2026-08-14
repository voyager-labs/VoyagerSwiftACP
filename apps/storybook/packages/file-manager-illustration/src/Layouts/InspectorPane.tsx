import type { FC } from "react"
import { AiChatView } from "../Domains/Chat/AiChatView"
import { SFSymbol } from "../Foundations/SFSymbol"
import type { AiChatInputBarActions, ChatSurfaceState } from "../model/types"

export type InspectorChatHeader = "sessions" | "chat"

export interface InspectorPaneProps {
  readonly chatHeader: InspectorChatHeader
  readonly requestText: string
  /** Derived chat title shown in the header (e.g. "Chat History" or session title). */
  readonly chatTitle: string
  readonly onRequestTextChange: (value: string) => void
  readonly onOpenChatHistory: () => void
  readonly onOpenNewChat: () => void
  readonly onCloseChat: () => void
  readonly onSessionSelected?: (id: string) => void
  readonly onOpenSettings?: () => void
  readonly onErrorRecovery?: () => void
  readonly onRegenerate?: () => void
  readonly onRebindContext?: () => void
  readonly onStartNewChatFromRebind?: () => void
  readonly chatInputActions?: AiChatInputBarActions
  // 지정 시 inspector 본문이 AiChatView가 된다. 생략 시 빈 화면 (native InspectorPaneView와 일치).
  readonly chatSurface?: ChatSurfaceState
}

export const InspectorPane: FC<InspectorPaneProps> = ({
  chatHeader,
  requestText,
  chatTitle,
  onRequestTextChange,
  onOpenChatHistory,
  onOpenNewChat,
  onCloseChat,
  onSessionSelected,
  onOpenSettings,
  onErrorRecovery,
  onRegenerate,
  onRebindContext,
  onStartNewChatFromRebind,
  chatInputActions,
  chatSurface,
}) => {
  return (
    <aside className="inspector" aria-label="Context Pane">
      {/* Chat-only header — mirrors native InspectorPaneView header */}
      <header className="inspector-header" data-chat-header={chatHeader}>
        {chatHeader === "sessions" ? (
          <>
            <span className="inspector-header-title">Chat History</span>
            <div className="inspector-header-actions">
              <button
                className="inspector-header-btn"
                type="button"
                aria-label="Start New Chat"
                onClick={onOpenNewChat}
              >
                New Chat
              </button>
              <button
                className="inspector-header-btn inspector-header-icon-btn"
                type="button"
                aria-label="Close AI Chat"
                onClick={onCloseChat}
              >
                <SFSymbol name="sidebar.trailing" size={16} />
              </button>
            </div>
          </>
        ) : (
          <>
            <button
              className="inspector-header-btn inspector-header-icon-btn"
              type="button"
              aria-label="Back to Chat History"
              onClick={onOpenChatHistory}
            >
              <SFSymbol name="chevron.left" size={16} />
            </button>
            <span className="inspector-header-title">{chatTitle}</span>
            <div className="inspector-header-actions">
              <button
                className="inspector-header-btn inspector-header-icon-btn"
                type="button"
                aria-label="Close AI Chat"
                onClick={onCloseChat}
              >
                <SFSymbol name="sidebar.trailing" size={16} />
              </button>
            </div>
          </>
        )}
      </header>

      {chatSurface != null ? (
        <AiChatView
          state={chatSurface}
          requestText={requestText}
          onRequestTextChange={onRequestTextChange}
          onSessionSelected={onSessionSelected}
          onOpenSettings={onOpenSettings}
          onErrorRecovery={onErrorRecovery}
          onRegenerate={onRegenerate}
          onRebindContext={onRebindContext}
          onStartNewChatFromRebind={onStartNewChatFromRebind}
          inputActions={chatInputActions}
        />
      ) : null}
    </aside>
  )
}

InspectorPane.displayName = "InspectorPane"
