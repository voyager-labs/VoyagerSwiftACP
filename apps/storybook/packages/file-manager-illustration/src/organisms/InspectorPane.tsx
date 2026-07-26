import type { FC } from "react"
import { FileManagerIcon } from "../FileManagerIcon"
import type { Entry } from "../types"

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
                <FileManagerIcon name="close" />
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
              <FileManagerIcon name="back" />
            </button>
            <span className="inspector-header-title">{chatTitle}</span>
            <div className="inspector-header-actions">
              <button
                className="inspector-header-btn"
                type="button"
                aria-label="Close AI Chat"
                onClick={onCloseChat}
              >
                <FileManagerIcon name="close" />
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
            <FileManagerIcon name="plus" />
            <em>GPT-5.2</em>
            <span className="vc-send-button">
              <FileManagerIcon name="send" />
            </span>
          </span>
        </label>
      </section>
    </aside>
  )
}

InspectorPane.displayName = "InspectorPane"
