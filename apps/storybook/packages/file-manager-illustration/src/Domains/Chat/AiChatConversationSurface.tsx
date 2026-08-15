import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type {
  AiChatInputBarActions,
  AiChatInputBarPresentation,
  ChatConnectionError,
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
  readonly onRegenerate?: () => void
  readonly connectionError?: ChatConnectionError
  readonly onConnectionAction?: () => void
  readonly rebindRequired?: boolean
  readonly onRebindContext?: () => void
  readonly onStartNewChatFromRebind?: () => void
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
  connectionError,
  onConnectionAction,
  rebindRequired,
  onRebindContext,
  onStartNewChatFromRebind,
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
        {rebindRequired === true ? (
          <AiChatStatusBanner
            bannerLabel="Rebind required"
            iconName="arrow.triangle.2.circlepath.circle"
            title="Session needs rebind"
            detail="Reconnect this chat to the current context, or start a clean chat."
            actions={[
              { label: "Rebind context", onClick: onRebindContext },
              { label: "Start new chat", onClick: onStartNewChatFromRebind },
            ]}
          />
        ) : null}
        {connectionError != null ? (
          <AiChatStatusBanner
            bannerLabel="AI provider status"
            iconName="bolt.horizontal.circle"
            title={connectionError.title}
            detail={connectionError.detail}
            actions={[{ label: connectionError.actionLabel, onClick: onConnectionAction }]}
          />
        ) : null}
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
                failure: streamingAssistant.failure,
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

interface AiChatStatusBannerAction {
  readonly label: string
  readonly onClick?: () => void
}

interface AiChatStatusBannerProps {
  readonly bannerLabel: string
  readonly iconName: string
  readonly title: string
  readonly detail: string
  readonly actions: readonly AiChatStatusBannerAction[]
}

// 원본: AiChatConversationSurface.swift AiChatStatusBanner / AiChatRebindRecoveryBanner.
// 두 배너는 동일 카드 anatomy라 클래스를 공유한다.
const AiChatStatusBanner: FC<AiChatStatusBannerProps> = ({
  bannerLabel,
  iconName,
  title,
  detail,
  actions,
}) => (
  <output className="chat-status-banner" aria-label={bannerLabel}>
    <div className="chat-status-banner-heading">
      <SFSymbol name={iconName} size={18} weight={500} />
      <div className="chat-status-banner-copy">
        <strong>{title}</strong>
        <p>{detail}</p>
      </div>
    </div>
    <div className="chat-status-banner-actions">
      {actions.map((action) => (
        <button
          key={action.label}
          type="button"
          className="chat-status-banner-action"
          onClick={action.onClick}
        >
          {action.label}
        </button>
      ))}
    </div>
  </output>
)

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
