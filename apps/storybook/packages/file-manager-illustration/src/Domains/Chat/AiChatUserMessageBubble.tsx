import type { FC, ReactNode } from "react"
import { AiChatCopyFeedback, type AiChatCopyFeedbackState } from "./AiChatCopyFeedback"

// AiChatMessageRow.userMessage 번역 — 사용자 메시지 버블.
// 원본: padding h14/v10, userMessageBubbleBackground(=inputBackground), Radius.userMessageBubble=20.

export interface AiChatUserMessageBubbleProps {
  readonly children: ReactNode
  readonly copyFeedback?: AiChatCopyFeedbackState
}

export const AiChatUserMessageBubble: FC<AiChatUserMessageBubbleProps> = ({
  children,
  copyFeedback,
}) => (
  <div className="chat-bubble chat-selectable-output" data-chat-role="user">
    {children}
    {copyFeedback == null ? null : <AiChatCopyFeedback state={copyFeedback} />}
  </div>
)

AiChatUserMessageBubble.displayName = "AiChatUserMessageBubble"
