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

// AiChatView 번역 — 프레젠테이션 상태(sessions/transcript/centeredEmpty/unconnected/connectionError)에 따라 본문을 전환한다.
// 원본: apps/macos/Packages/04_Features/AiChat/Sources/VoyagerFeaturesAiChat/Ui/AiChatView.swift (AiChatViewPresentation.resolve).

export interface AiChatViewProps {
  readonly state: ChatSurfaceState
  readonly requestText: string
  readonly onRequestTextChange: (value: string) => void
  readonly onSessionSelected?: (id: string) => void
  readonly onOpenSettings?: () => void
  readonly onErrorRecovery?: () => void
  readonly onRegenerate?: () => void
  readonly onRebindContext?: () => void
  readonly onStartNewChatFromRebind?: () => void
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
  onRebindContext,
  onStartNewChatFromRebind,
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
          rebindRequired={state.rebindRequired}
          onRebindContext={onRebindContext}
          onStartNewChatFromRebind={onStartNewChatFromRebind}
        />
      )
    case "unconnected":
      return (
        <AiChatConversationSurface
          messages={state.messages ?? []}
          statusText={state.statusText}
          canRegenerate={state.canRegenerate}
          requestText={requestText}
          onRequestTextChange={onRequestTextChange}
          inputPresentation={state.inputBar}
          inputActions={inputActions}
          connectionError={state.connectionError}
          onConnectionAction={onOpenSettings}
        />
      )
    case "connectionError":
      return (
        <AiChatConversationSurface
          messages={state.messages ?? []}
          statusText={state.statusText}
          canRegenerate={state.canRegenerate}
          requestText={requestText}
          onRequestTextChange={onRequestTextChange}
          inputPresentation={state.inputBar}
          inputActions={inputActions}
          connectionError={state.connectionError}
          onConnectionAction={onErrorRecovery}
        />
      )
    case "centeredEmpty":
      return (
        <section className="chat-empty" aria-label="Empty chat">
          <div className="chat-empty-copy">
            <div className="chat-empty-content">
              <span className="chat-empty-icon" aria-hidden="true">
                <SFSymbol name="bubble.left.and.text.bubble.right" size={28} />
              </span>
              <strong>{state.emptyTitle}</strong>
              <p>{state.emptyDetail}</p>
            </div>
            {state.connectionError != null ? (
              <AiChatCompactConnectionCta
                cta={state.connectionError}
                onOpenSettings={onOpenSettings}
              />
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

interface AiChatCompactConnectionCtaProps {
  readonly cta: ChatConnectionError
  readonly onOpenSettings?: () => void
}

// 원본: AiChatView.swift compactConnectionCTA — content page centeredEmpty 하단 가로 CTA.
const AiChatCompactConnectionCta: FC<AiChatCompactConnectionCtaProps> = ({
  cta,
  onOpenSettings,
}) => (
  <div className="chat-connection-cta">
    <SFSymbol name="bolt.horizontal.circle" size={17} weight={500} />
    <div className="chat-connection-cta-copy">
      <strong>{cta.title}</strong>
      <p>{cta.detail}</p>
    </div>
    <button type="button" className="chat-connection-cta-action" onClick={onOpenSettings}>
      {cta.actionLabel}
    </button>
  </div>
)
