import type { FC, ReactNode } from "react"

// AiChatMessageRow.userMessage 번역 — 사용자 메시지 버블.
// 원본: padding h14/v10, userMessageBubbleBackground(=inputBackground), Radius.userMessageBubble=20.

export interface ChatMessageBubbleProps {
  readonly children: ReactNode
}

export const ChatMessageBubble: FC<ChatMessageBubbleProps> = ({ children }) => (
  <div className="chat-bubble">{children}</div>
)

ChatMessageBubble.displayName = "ChatMessageBubble"
