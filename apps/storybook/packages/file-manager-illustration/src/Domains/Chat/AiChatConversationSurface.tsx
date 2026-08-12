import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type {
  AiChatInputBarActions,
  AiChatInputBarPresentation,
  ChatMessage,
  ChatStreamingAssistant,
} from "../../model/types"
import { AiChatAssistantCard } from "./AiChatAssistantCard"
import { resolveAiChatAssistantPresentation } from "./AiChatAssistantPresentation"
import { AiChatInputBar } from "./AiChatInputBar"
import { AiChatUserMessageBubble } from "./AiChatUserMessageBubble"

// AiChatConversationSurface 번역 — 메시지 행 + streaming 카드 + status + composer를 조립.
// 원본: apps/macos/.../AiChatConversationSurface.swift (AiChatTranscriptSection, AiChatMessageRow).

export interface AiChatConversationSurfaceProps {
  readonly messages: readonly ChatMessage[]
  readonly streamingAssistant?: ChatStreamingAssistant
  readonly isProcessing?: boolean
  readonly statusText?: string
  readonly canRegenerate?: boolean
  readonly requestText: string
  readonly onRequestTextChange: (value: string) => void
  readonly inputPresentation: AiChatInputBarPresentation
  readonly inputActions?: AiChatInputBarActions
  readonly onErrorRecovery?: () => void
  readonly onRegenerate?: () => void
}

export const AiChatConversationSurface: FC<AiChatConversationSurfaceProps> = ({
  messages,
  streamingAssistant,
  isProcessing,
  statusText,
  canRegenerate,
  requestText,
  onRequestTextChange,
  inputPresentation,
  inputActions,
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
          <AiChatMessageRow
            key={message.id}
            message={message}
            showsRegenerate={canRegenerate === true && index === lastAssistantIndex}
            onRegenerate={onRegenerate}
          />
        ))}

        {streamingAssistant != null ? (
          <div className="chat-message-assistant" data-chat-role="assistant">
            <AiChatAssistantCard
              presentation={resolveAiChatAssistantPresentation({
                title: streamingAssistant.title,
                thinkingLabel: streamingAssistant.thinkingLabel,
                activityStatusLabel: streamingAssistant.activityStatusLabel,
                content: streamingAssistant.content,
                isProcessing,
                failure: streamingAssistant.failure?.message,
              })}
            />
          </div>
        ) : isProcessing === true ? (
          <div className="chat-message-assistant" data-chat-role="assistant">
            <AiChatAssistantCard
              presentation={resolveAiChatAssistantPresentation({
                title: "Assistant",
                isProcessing: true,
              })}
            />
          </div>
        ) : statusText != null && statusText !== "" ? (
          <p className="chat-status-row">{statusText}</p>
        ) : null}
      </div>

      <div className="chat-input-bar-frame">
        <AiChatInputBar
          requestText={requestText}
          onRequestTextChange={onRequestTextChange}
          presentation={inputPresentation}
          actions={inputActions}
        />
      </div>
    </section>
  )
}

AiChatConversationSurface.displayName = "AiChatConversationSurface"

interface AiChatMessageRowProps {
  readonly message: ChatMessage
  readonly showsRegenerate?: boolean
  readonly onRegenerate?: () => void
}

// AiChatMessageRow 번역 — user(버블) / assistant(카드+regenerate) / system(tool) 분기.
const AiChatMessageRow: FC<AiChatMessageRowProps> = ({
  message,
  showsRegenerate,
  onRegenerate,
}) => {
  const timestamp = message.timestamp
  const showsTimestampAffordance =
    timestamp != null && timestamp.isTimestampVisuallySuppressed !== true

  if (message.role === "user") {
    return (
      <div className="chat-message-user" data-chat-role="user">
        <div className="chat-user-bubble-frame">
          {showsTimestampAffordance ? (
            <span
              className="chat-timestamp chat-timestamp-user"
              aria-label={`Sent ${timestamp.label}`}
              title={timestamp.label}
            >
              <SFSymbol name="clock" size={11} />
            </span>
          ) : null}
          <AiChatUserMessageBubble>{message.content}</AiChatUserMessageBubble>
        </div>
      </div>
    )
  }

  if (message.role === "assistant") {
    return (
      <div className="chat-message-assistant" data-chat-role="assistant">
        <div className="chat-assistant-card-frame">
          <AiChatAssistantCard
            presentation={resolveAiChatAssistantPresentation({
              title: "Assistant",
              content: message.content,
              headerPresentation: "completedHistorical",
            })}
          />
          {showsTimestampAffordance ? (
            <span
              className="chat-timestamp chat-timestamp-assistant"
              aria-label={`Received ${timestamp.label}`}
              title={timestamp.label}
            >
              <SFSymbol name="clock" size={11} />
            </span>
          ) : null}
        </div>
        {showsRegenerate ? (
          <div className="chat-regenerate-action">
            <button
              type="button"
              className="chat-regenerate"
              onClick={onRegenerate}
              aria-label="Regenerate response"
            >
              <SFSymbol name="arrow.clockwise" size={12} />
            </button>
            <span className="chat-regenerate-label">Regenerate response</span>
          </div>
        ) : null}
      </div>
    )
  }

  // system / tool
  return <p className="chat-status-row">{message.content}</p>
}
