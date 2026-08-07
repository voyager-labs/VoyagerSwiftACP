import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import { ChatWaitingIndicator } from "./ChatWaitingIndicator"

// AiChatAssistantCard 번역 — header/body/failure 3분기 + 5상태 기기.
// 원본: apps/macos/.../AiChatConversationSurface.swift (AiChatAssistantCard, AiChatAssistantBodyPresentation).
// VStack(leading, spacing 12) padding v4; showsInlineHeader(full && content==nil && failure==nil);
// showsWaiting(processing && failure==nil && content==nil).

export interface ChatAssistantCardProps {
  readonly title: string
  readonly thinkingLabel?: string
  readonly activityStatusLabel?: string
  readonly content?: string
  readonly isProcessing?: boolean
  readonly failure?: string
  readonly headerPresentation?: "full" | "completedHistorical"
}

export const ChatAssistantCard: FC<ChatAssistantCardProps> = ({
  title,
  thinkingLabel,
  activityStatusLabel,
  content,
  isProcessing,
  failure,
  headerPresentation = "full",
}) => {
  const normalizedContent = content != null && content.trim() !== "" ? content : undefined
  const showsInlineHeader =
    headerPresentation === "full" && normalizedContent == null && failure == null
  const showsWaiting = isProcessing === true && failure == null && normalizedContent == null

  return (
    <article className="chat-assistant-card">
      {showsInlineHeader ? (
        <header className="chat-assistant-header">
          <span className="chat-assistant-title">{title}</span>
          {thinkingLabel != null && thinkingLabel !== "" ? (
            <span className="chat-thinking">{thinkingLabel}</span>
          ) : null}
          {activityStatusLabel != null && activityStatusLabel !== "" ? (
            <span className="chat-activity">{activityStatusLabel}</span>
          ) : null}
        </header>
      ) : null}

      {normalizedContent != null ? (
        <p className="chat-message-content">{normalizedContent}</p>
      ) : showsWaiting ? (
        <ChatWaitingIndicator />
      ) : null}

      {failure != null && failure !== "" ? (
        <div className="chat-failure" role="alert">
          <span className="chat-failure-icon">
            <SFSymbol name="exclamationmark.triangle.fill" size={10} />
          </span>
          <span className="chat-failure-message">{failure}</span>
        </div>
      ) : null}
    </article>
  )
}

ChatAssistantCard.displayName = "ChatAssistantCard"
