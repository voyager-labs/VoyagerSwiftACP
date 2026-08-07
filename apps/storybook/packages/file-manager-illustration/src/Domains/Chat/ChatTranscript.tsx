import { useEffect, useState } from "react"
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
            title={streamingAssistant.title}
            thinkingLabel={streamingAssistant.thinkingLabel}
            activityStatusLabel={streamingAssistant.activityStatusLabel}
            content={streamingAssistant.content}
            isProcessing={isProcessing}
            failure={streamingAssistant.failure?.message}
          />
        ) : isProcessing === true ? (
          <ChatAssistantCard title="Assistant" isProcessing={true} />
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
  if (message.role === "user") {
    return (
      <div className="chat-message-user">
        <div className="chat-bubble">{message.content}</div>
      </div>
    )
  }

  if (message.role === "assistant") {
    return (
      <div className="chat-message-assistant">
        <ChatAssistantCard
          title="Assistant"
          content={message.content}
          headerPresentation="completedHistorical"
        />
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
      </div>
    )
  }

  // system / tool
  return <p className="chat-status-row">{message.content}</p>
}

interface ChatAssistantCardProps {
  readonly title: string
  readonly thinkingLabel?: string
  readonly activityStatusLabel?: string
  readonly content?: string
  readonly isProcessing?: boolean
  readonly failure?: string
  readonly headerPresentation?: "full" | "completedHistorical"
}

const ChatAssistantCard: FC<ChatAssistantCardProps> = ({
  title,
  thinkingLabel,
  activityStatusLabel,
  content,
  isProcessing,
  failure,
  headerPresentation = "full",
}) => {
  const normalizedContent = content != null && content.trim() !== "" ? content : undefined
  // 네이티브 AiChatAssistantBodyPresentation: header는 content·failure 둘 다 없을 때만(full).
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

// AiChatWaitingIndicator 번역 — 0.4s 주기로 "."/".."/"..." 순환, reduce-motion 시 정지.
const ChatWaitingIndicator: FC = () => {
  const reduceMotion =
    typeof window !== "undefined" &&
    typeof window.matchMedia === "function" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  const [step, setStep] = useState(0)

  useEffect(() => {
    if (reduceMotion) return
    const id = window.setInterval(() => {
      setStep((prev) => (prev + 1) % 3)
    }, 400)
    return () => window.clearInterval(id)
  }, [reduceMotion])

  const dots = ".".repeat((reduceMotion ? 2 : step) + 1)
  return (
    <span className="chat-waiting" aria-label="Waiting for assistant response">
      {dots}
    </span>
  )
}
