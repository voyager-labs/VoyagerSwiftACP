import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type { ChatConnectionError, ChatSurfaceState } from "../../model/types"
import { ChatSessions } from "./ChatSessions"
import { ChatTranscript } from "./ChatTranscript"

// AiChatView 번역 — 프레젠테이션 상태(sessions/transcript/centeredEmpty)에 따라 본문을 전환한다.
// 원본: apps/macos/Packages/04_Features/AiChat/Sources/VoyagerFeaturesAiChat/Ui/AiChatView.swift (AiChatViewPresentation.resolve).

export interface ChatSurfaceProps {
  readonly state: ChatSurfaceState
  readonly requestText: string
  readonly onRequestTextChange: (value: string) => void
  readonly onSessionSelected?: (id: string) => void
  readonly onOpenSettings?: () => void
  readonly onErrorRecovery?: () => void
  readonly onRegenerate?: () => void
}

export const ChatSurface: FC<ChatSurfaceProps> = ({
  state,
  requestText,
  onRequestTextChange,
  onSessionSelected,
  onOpenSettings,
  onErrorRecovery,
  onRegenerate,
}) => {
  switch (state.kind) {
    case "sessions":
      return (
        <ChatSessions
          sections={state.sections}
          errorMessage={state.errorMessage}
          isLoading={state.isLoading}
          emptyTitle={state.emptyTitle}
          emptyDetail={state.emptyDetail}
          onSessionSelected={onSessionSelected}
        />
      )
    case "transcript":
      return (
        <ChatTranscript
          messages={state.messages}
          streamingAssistant={state.streamingAssistant}
          isProcessing={state.isProcessing}
          statusText={state.statusText}
          canRegenerate={state.canRegenerate}
          requestText={requestText}
          onRequestTextChange={onRequestTextChange}
          onErrorRecovery={onErrorRecovery}
          onRegenerate={onRegenerate}
        />
      )
    case "centeredEmpty":
      return (
        <section className="chat-empty" aria-label="Empty chat">
          <div className="chat-empty-content">
            <strong>{state.emptyTitle}</strong>
            <p>{state.emptyDetail}</p>
          </div>
          {state.connectionError != null ? (
            <ChatConnectionCta cta={state.connectionError} onOpenSettings={onOpenSettings} />
          ) : null}
        </section>
      )
  }
}

ChatSurface.displayName = "ChatSurface"

interface ChatConnectionCtaProps {
  readonly cta: ChatConnectionError
  readonly onOpenSettings?: () => void
}

const ChatConnectionCta: FC<ChatConnectionCtaProps> = ({ cta, onOpenSettings }) => (
  <div className="chat-connection-cta">
    <SFSymbol name="bolt.horizontal.circle" size={17} />
    <div className="chat-connection-cta-copy">
      <strong>{cta.title}</strong>
      <p>{cta.detail}</p>
    </div>
    <button type="button" className="chat-connection-cta-action" onClick={onOpenSettings}>
      {cta.actionLabel}
    </button>
  </div>
)
