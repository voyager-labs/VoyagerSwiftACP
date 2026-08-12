import type { FC, ReactNode } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { ChatFailure } from "../../model/types"
import { AiChatAssistantMarkdownText } from "./AiChatAssistantMarkdownText"
import type {
  AiChatAssistantHeaderPresentation,
  AiChatAssistantPresentation,
} from "./AiChatAssistantPresentation"
import { AiChatWaitingIndicator } from "./AiChatWaitingIndicator"

// 원본: apps/macos/.../AiChatConversationSurface.swift (AiChatAssistantCard, AiChatAssistantBodyPresentation).

export interface AiChatAssistantCardProps {
  readonly presentation: AiChatAssistantPresentation
  readonly onErrorRecovery?: () => void
}

export const AiChatAssistantCard: FC<AiChatAssistantCardProps> = ({
  presentation,
  onErrorRecovery,
}) => {
  return (
    <article className="chat-assistant-card" data-chat-state={presentation.kind}>
      {renderPresentation(presentation, onErrorRecovery)}
    </article>
  )
}

AiChatAssistantCard.displayName = "AiChatAssistantCard"

function renderPresentation(
  presentation: AiChatAssistantPresentation,
  onErrorRecovery?: () => void,
): ReactNode {
  switch (presentation.kind) {
    case "waiting":
      return (
        <>
          <AssistantHeader presentation={presentation.header} />
          <AiChatWaitingIndicator />
        </>
      )
    case "streaming":
      return <AiChatAssistantMarkdownText content={presentation.content} />
    case "partial-failure":
      return (
        <>
          <AiChatAssistantMarkdownText content={presentation.content} />
          <AssistantFailure failure={presentation.failure} onRecovery={onErrorRecovery} />
        </>
      )
    case "terminal-failure":
      return <AssistantFailure failure={presentation.failure} onRecovery={onErrorRecovery} />
    case "completed":
      return (
        <>
          {presentation.header == null ? null : (
            <AssistantHeader presentation={presentation.header} />
          )}
          {presentation.content == null ? null : (
            <AiChatAssistantMarkdownText content={presentation.content} />
          )}
          {presentation.failure == null ? null : (
            <AssistantFailure failure={presentation.failure} onRecovery={onErrorRecovery} />
          )}
        </>
      )
    default:
      return assertNever(presentation)
  }
}

const AssistantHeader: FC<{ readonly presentation: AiChatAssistantHeaderPresentation }> = ({
  presentation,
}) => (
  <header className="chat-assistant-header">
    <span className="chat-assistant-title">{presentation.title}</span>
    {presentation.thinkingLabel == null ? null : (
      <span className="chat-thinking">{presentation.thinkingLabel}</span>
    )}
    {presentation.activityStatusLabel == null ? null : (
      <span className="chat-activity">{presentation.activityStatusLabel}</span>
    )}
  </header>
)

const AssistantFailure: FC<{
  readonly failure: ChatFailure
  readonly onRecovery?: () => void
}> = ({ failure, onRecovery }) => (
  <div className="chat-failure" role="alert">
    <span className="chat-failure-icon">
      <SFSymbol name="exclamationmark.triangle.fill" size={10} />
    </span>
    <span className="chat-failure-message">{failure.message}</span>
    {failure.recoveryLabel == null ? null : (
      <button
        type="button"
        className="chat-failure-recovery"
        disabled={onRecovery == null}
        aria-label={failure.recoveryLabel}
        onClick={onRecovery}
      >
        {failure.recoveryLabel}
      </button>
    )}
  </div>
)

function assertNever(value: never): never {
  return value
}
