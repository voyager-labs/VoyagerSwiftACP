import type { AiChatState } from "./types"

const sessions = [
  {
    id: "s1",
    title: "Review collection PDFs",
    status: "active" as const,
    meta: "5 selected files",
  },
  { id: "s2", title: "Brand assets summary", status: "completed" as const, meta: "Yesterday" },
  { id: "s3", title: "Recover failed transcript", status: "failed" as const, meta: "Needs retry" },
]

const messages = [
  {
    id: "m1",
    author: "user" as const,
    text: "Summarize the selected collection files.",
    meta: "You · 10:42",
  },
  {
    id: "m2",
    author: "assistant" as const,
    text: "I found three related topics and two documents that look like source references.",
    meta: "Voyager AI · 10:43",
  },
]

export const readyChat: AiChatState = {
  mode: "chat",
  executionPhase: "completed",
  modelState: "loaded",
  selectedModel: "Claude Sonnet 4",
  sessions,
  selectedSessionId: "s1",
  contextSummary: "5 PDFs from Research Collection",
  contextCount: 5,
  draftText: "Compare the recurring themes.",
  messages,
  attachments: [{ id: "a1", label: "Source Notes.pdf", status: "resolved" }],
}

export const sessionsChat: AiChatState = {
  ...readyChat,
  mode: "sessions",
  executionPhase: "idle",
  draftText: "",
}

export const processingChat: AiChatState = {
  ...readyChat,
  executionPhase: "processing",
  modelState: "locked",
  streamingText: "Reading the selected files and grouping related references…",
  attachments: [
    { id: "a1", label: "Source Notes.pdf", status: "resolved" },
    { id: "a2", label: "Reference Summary.pdf", status: "pending" },
  ],
}

export const unconnectedChat: AiChatState = {
  ...readyChat,
  executionPhase: "idle",
  modelState: "empty",
  selectedModel: "No provider connected",
  contextSummary: "No current selection",
  contextCount: 0,
  messages: [],
  draftText: "",
  attachments: [],
}

export const failedChat: AiChatState = {
  ...readyChat,
  executionPhase: "failed",
  modelState: "unavailable",
  failure: "The selected model is no longer available. Choose another model to continue.",
  attachments: [{ id: "a3", label: "Missing reference", status: "failed" }],
}
