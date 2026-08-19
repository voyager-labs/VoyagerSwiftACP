import type { FC } from "react"

export type AiChatCopyFeedbackState = "copied" | "failed"

export interface AiChatCopyFeedbackProps {
  readonly state: AiChatCopyFeedbackState
}

export const AiChatCopyFeedback: FC<AiChatCopyFeedbackProps> = ({ state }) => (
  <output className="chat-copy-feedback" data-copy-feedback={state}>
    {state === "copied" ? "Copied" : "Couldn’t copy. Try again."}
  </output>
)

AiChatCopyFeedback.displayName = "AiChatCopyFeedback"
