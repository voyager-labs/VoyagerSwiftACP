import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { ChatMessage, ChatStreamingAssistant } from "../../model/types"
import { InspectorChatInput } from "./InspectorChatInput"

// AiChatConversationSurface / AiChatTranscriptSection 번역 — 메시지 행 + streaming 카드 + status + composer.
// 원본: apps/macos/Packages/04_Features/AiChat/Sources/VoyagerFeaturesAiChat/Ui/AiChatConversationSurface.swift.

export interface ChatTranscriptProps {
  readonly messages: readonly ChatMessage[]
  readonly streamingAssistant?: ChatStreamingAssistant
  readonly isProcessing?: boolean
  readonly statusText?: string
  readonly canRegenerate?: boolean
  readonly requestText: string
  readonly onRequestTextChange: (value: string) => void
  readonly onErrorRecovery?: () => void
  readonly onRegenerate?: () => void
}

export const ChatTranscript: FC<ChatTranscriptProps> = ({
  messages,
  streamingAssistant,
  isProcessing,
  statusText,
  canRegenerate,
  requestText,
  onRequestTextChange,
  onErrorRecovery,
  onRegenerate,
}) => {
  const lastAssistantIndex = (() => {
    for (let i = messages.length - 1; i >= 0; i -= 1) {
      if (messages[i].role === "assistant") return i
    }
    return undefined
  })()

  return (
    <section className="chat-transcript" aria-label="Conversation" aria-live="polite">
      <div className="chat-transcript-scroll">
        {messages.map((message, index) => (
          <ChatMessageRow
            key={message.id}
            message={message}
            showsRegenerate={canRegenerate === true && index === lastAssistantIndex}
            onRegenerate={onRegenerate}
          />
        ))}

        {streamingAssistant != null ? (
          <ChatAssistantCard
            assistant={streamingAssistant}
            isProcessing={isProcessing}
            onErrorRecovery={onErrorRecovery}
          />
        ) : isProcessing === true ? (
          <ChatAssistantCard
            assistant={{ title: "Assistant", content: undefined }}
            isProcessing={true}
            onErrorRecovery={onErrorRecovery}
          />
        ) : statusText != null && statusText !== "" ? (
          <p className="chat-status-row">{statusText}</p>
        ) : null}
      </div>

      <InspectorChatInput requestText={requestText} onRequestTextChange={onRequestTextChange} />
    </section>
  )
}

ChatTranscript.displayName = "ChatTranscript"

interface ChatMessageRowProps {
  readonly message: ChatMessage
  readonly showsRegenerate?: boolean
  readonly onRegenerate?: () => void
}

const ChatMessageRow: FC<ChatMessageRowProps> = ({ message, showsRegenerate, onRegenerate }) => {
  const isUser = message.role === "user"
  return (
    <article className={`chat-message chat-message-${message.role}`}>
      <span className="chat-message-role">{isUser ? "You" : "Assistant"}</span>
      <p className="chat-message-content">{message.content}</p>
      <span className="chat-message-meta">
        {message.timestamp != null ? <time>{message.timestamp}</time> : null}
        {showsRegenerate ? (
          <button
            type="button"
            className="chat-regenerate"
            onClick={onRegenerate}
            aria-label="Regenerate response"
          >
            <SFSymbol name="arrow.clockwise" size={12} />
          </button>
        ) : null}
      </span>
    </article>
  )
}

interface ChatAssistantCardProps {
  readonly assistant: ChatStreamingAssistant
  readonly isProcessing?: boolean
  readonly onErrorRecovery?: () => void
}

const ChatAssistantCard: FC<ChatAssistantCardProps> = ({
  assistant,
  isProcessing,
  onErrorRecovery,
}) => {
  const hasContent = assistant.content != null && assistant.content !== ""
  return (
    <article className={`chat-assistant-card${isProcessing === true ? " is-processing" : ""}`}>
      <span className="chat-message-role">{assistant.title}</span>
      {assistant.thinkingLabel != null && isProcessing === true ? (
        <span className="chat-thinking">
          <span className="chat-spinner" aria-hidden="true" />
          {assistant.thinkingLabel}
        </span>
      ) : null}
      {assistant.activityStatusLabel != null && isProcessing === true ? (
        <span className="chat-activity">{assistant.activityStatusLabel}</span>
      ) : null}
      {hasContent ? <p className="chat-message-content">{assistant.content}</p> : null}
      {assistant.failure != null ? (
        <div className="chat-failure" role="alert">
          <SFSymbol name="exclamationmark.triangle" size={14} />
          <span>{assistant.failure.message}</span>
          <button type="button" className="chat-recovery" onClick={onErrorRecovery}>
            {assistant.failure.recoveryLabel ?? "Retry"}
          </button>
        </div>
      ) : null}
    </article>
  )
}
