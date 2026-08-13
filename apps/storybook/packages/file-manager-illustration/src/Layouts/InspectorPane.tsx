import type { FC } from "react"
import { AiChatView } from "../Domains/Chat/AiChatView"
import { SFSymbol } from "../Foundations/SFSymbol"
import type { AiChatInputBarActions, ChatSurfaceState, Entry } from "../model/types"

export type InspectorChatHeader = "sessions" | "chat"

export interface InspectorPaneProps {
  readonly chatHeader: InspectorChatHeader
  readonly requestText: string
  readonly selectedEntries: readonly Entry[]
  readonly primaryEntry: Entry | null
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
  readonly chatInputActions?: AiChatInputBarActions
  // 제공 시 inspector 본문이 AiChatView가 된다. 생략 시 기본 composer 본문.
  readonly chatSurface?: ChatSurfaceState
}

export const InspectorPane: FC<InspectorPaneProps> = ({
  chatHeader,
  requestText,
  selectedEntries,
  primaryEntry,
  chatTitle,
  onRequestTextChange,
  onOpenChatHistory,
  onOpenNewChat,
  onCloseChat,
  onSessionSelected,
  onOpenSettings,
  onErrorRecovery,
  onRegenerate,
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
          inputActions={chatInputActions}
        />
      ) : (
        <section className="chat-pane">
          {primaryEntry != null && (
            <div className="quiet-card">
              <span className="eyebrow">Selected Entry</span>
              <strong>{primaryEntry.name}</strong>
              <p>{selectedEntries.length} selected</p>
            </div>
          )}
          <label className="composer">
            <textarea
              rows={5}
              placeholder="Ask anything…"
              value={requestText}
              onInput={(e) => onRequestTextChange(e.currentTarget.value)}
            />
            <span className="composer-footer">
              <SFSymbol name="plus" size={16} />
              <em>GPT-5.2</em>
              <span className="vc-send-button">
                <SFSymbol name="arrow.up" size={16} />
              </span>
            </span>
          </label>
        </section>
      )}
    </aside>
  )
}

InspectorPane.displayName = "InspectorPane"
