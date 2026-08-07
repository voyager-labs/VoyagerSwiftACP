import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { ChatSessionSection } from "../../model/types"

// AiChatSessionsView 번역 — 검색 필드, 선택적 에러, empty(로딩/title/detail), sections(rows) hover.
// 원본: apps/macos/Packages/04_Features/AiChat/Sources/VoyagerFeaturesAiChat/Ui/AiChatSessionsView.swift.

export interface ChatSessionsProps {
  readonly sections: readonly ChatSessionSection[]
  readonly errorMessage?: string
  readonly isLoading?: boolean
  readonly emptyTitle?: string
  readonly emptyDetail?: string
  readonly onSessionSelected?: (id: string) => void
}

export const ChatSessions: FC<ChatSessionsProps> = ({
  sections,
  errorMessage,
  isLoading,
  emptyTitle,
  emptyDetail,
  onSessionSelected,
}) => {
  const isEmpty = sections.every((section) => section.rows.length === 0)

  return (
    <section className="chat-sessions" aria-label="Chat History">
      <div className="chat-sessions-search">
        <SFSymbol name="magnifyingglass" size={13} />
        <input type="search" placeholder="Search" aria-label="Search chat history" readOnly />
      </div>

      {errorMessage != null && errorMessage !== "" ? (
        <p className="chat-sessions-error" role="alert">
          {errorMessage}
        </p>
      ) : null}

      {isEmpty ? (
        isLoading ? (
          <div className="chat-sessions-loading" aria-live="polite">
            <span className="chat-spinner" aria-hidden="true" />
            <span>Loading sessions…</span>
          </div>
        ) : (
          <div className="chat-sessions-empty">
            <strong>{emptyTitle ?? "No chats yet"}</strong>
            <p>{emptyDetail ?? "Start a new chat to see it here."}</p>
          </div>
        )
      ) : (
        <div className="chat-sessions-scroll">
          {sections.map((section) => (
            <div key={section.id} className="chat-sessions-section">
              <span className="chat-sessions-section-title">{section.title}</span>
              {section.rows.map((row) => (
                <button
                  key={row.id}
                  type="button"
                  className="chat-sessions-row"
                  onClick={() => onSessionSelected?.(row.id)}
                >
                  <span className="chat-sessions-row-title">{row.title}</span>
                  {row.detail != null ? (
                    <span className="chat-sessions-row-detail">{row.detail}</span>
                  ) : null}
                </button>
              ))}
            </div>
          ))}
        </div>
      )}
    </section>
  )
}

ChatSessions.displayName = "ChatSessions"
