export type AiChatMode = "sessions" | "chat"

export type AiExecutionPhase =
  | "idle"
  | "processing"
  | "completed"
  | "failed"
  | "cancelled"
  | "persistenceRecovery"

export type AiModelState = "loading" | "loaded" | "empty" | "failed" | "locked" | "unavailable"

export type AttachmentStatus = "pending" | "resolved" | "failed"

export type ChatMessage = {
  readonly id: string
  readonly author: "user" | "assistant"
  readonly text: string
  readonly meta: string
}

export type ChatSession = {
  readonly id: string
  readonly title: string
  readonly status: "idle" | "restoring" | "active" | "completed" | "failed" | "rebindRequired"
  readonly meta: string
}

export type ChatAttachment = {
  readonly id: string
  readonly label: string
  readonly status: AttachmentStatus
}

export type AiChatState = {
  readonly mode: AiChatMode
  readonly executionPhase: AiExecutionPhase
  readonly modelState: AiModelState
  readonly selectedModel: string
  readonly sessions: readonly ChatSession[]
  readonly selectedSessionId?: string
  readonly contextSummary: string
  readonly contextCount: number
  readonly draftText: string
  readonly messages: readonly ChatMessage[]
  readonly attachments: readonly ChatAttachment[]
  readonly failure?: string
  readonly streamingText?: string
}
