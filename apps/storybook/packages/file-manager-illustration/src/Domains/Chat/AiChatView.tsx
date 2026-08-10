import type { FC } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"
import type {
  AiChatInputBarActions,
  ChatConnectionError,
  ChatSurfaceState,
} from "../../model/types"
import { AiChatConversationSurface } from "./AiChatConversationSurface"
import { AiChatInputBar } from "./AiChatInputBar"
import { AiChatSessionsView } from "./AiChatSessionsView"

// AiChatView 번역 — 프레젠테이션 상태(sessions/transcript/centeredEmpty)에 따라 본문을 전환한다.
// 원본: apps/macos/Packages/04_Features/AiChat/Sources/VoyagerFeaturesAiChat/Ui/AiChatView.swift (AiChatViewPresentation.resolve).

export interface AiChatViewProps {
  readonly state: ChatSurfaceState
  readonly requestText: string
  readonly onRequestTextChange: (value: string) => void
  readonly onSessionSelected?: (id: string) => void
  readonly onOpenSettings?: () => void
  readonly onErrorRecovery?: () => void
  readonly onRegenerate?: () => void
  readonly inputActions?: AiChatInputBarActions
}

export const AiChatView: FC<AiChatViewProps> = ({
  state,
  requestText,
  onRequestTextChange,
  onSessionSelected,
  onOpenSettings,
  onErrorRecovery,
  onRegenerate,
  inputActions,
}) => {
  switch (state.kind) {
    case "sessions":
      return (
        <AiChatSessionsView
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
        <AiChatConversationSurface
          messages={state.messages}
          streamingAssistant={state.streamingAssistant}
          isProcessing={state.isProcessing}
          statusText={state.statusText}
          canRegenerate={state.canRegenerate}
          requestText={requestText}
          onRequestTextChange={onRequestTextChange}
          inputPresentation={state.inputBar}
          inputActions={inputActions}
          onErrorRecovery={onErrorRecovery}
          onRegenerate={onRegenerate}
        />
      )
    case "centeredEmpty":
      return (
        <section className="chat-empty" aria-label="Empty chat">
          <div className="chat-empty-copy">
            <div className="chat-empty-content">
              <strong>{state.emptyTitle}</strong>
              <p>{state.emptyDetail}</p>
            </div>
            {state.connectionError != null ? (
              <AiChatConnectionCta cta={state.connectionError} onOpenSettings={onOpenSettings} />
            ) : null}
          </div>
          <div className="chat-input-bar-frame is-centered-empty">
            <AiChatInputBar
              requestText={requestText}
              onRequestTextChange={onRequestTextChange}
              presentation={state.inputBar}
              actions={inputActions}
            />
          </div>
        </section>
      )
  }
}

AiChatView.displayName = "AiChatView"

interface AiChatConnectionCtaProps {
  readonly cta: ChatConnectionError
  readonly onOpenSettings?: () => void
}

const AiChatConnectionCta: FC<AiChatConnectionCtaProps> = ({ cta, onOpenSettings }) => (
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
