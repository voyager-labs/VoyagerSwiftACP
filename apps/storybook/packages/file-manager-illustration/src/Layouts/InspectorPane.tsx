import type { FC } from "react"
import { SFSymbol } from "../Foundations/SFSymbol"
import type { Entry } from "../model/types"

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
}) => {
  return (
    <aside className="inspector" aria-label="Context Pane">
      {/* Chat-only header — mirrors native InspectorPaneView header */}
      <header className="inspector-header">
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
                className="inspector-header-btn"
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
              className="inspector-header-btn"
              type="button"
              aria-label="Back to Chat History"
              onClick={onOpenChatHistory}
            >
              <SFSymbol name="chevron.left" size={16} />
            </button>
            <span className="inspector-header-title">{chatTitle}</span>
            <div className="inspector-header-actions">
              <button
                className="inspector-header-btn"
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

      {/* Chat content area */}
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
    </aside>
  )
}

InspectorPane.displayName = "InspectorPane"
