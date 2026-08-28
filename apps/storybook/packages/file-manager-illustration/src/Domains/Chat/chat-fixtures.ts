import type {
  ChatConnectionError,
  ChatMessage,
  ChatSessionSection,
  ChatStreamingAssistant,
  ChatSurfaceState,
} from "../../model/types"
import {
  aiChatInputProcessing,
  aiChatInputReadyEmpty,
  aiChatInputUnconnected,
} from "./ai-chat-input-fixtures"

// 채팅 도메인 deterministic fixture — network·clock·random 미의존.
// 원본: AiChatState (sessionList, transcriptHistory, streamingAssistantDisplayModel).

export const chatRichMarkdownContent = [
  "## Research summary",
  "",
  "The **citation group** contains *two likely duplicates* and one `survey.pdf` source.",
  "",
  "> Keep the longer survey and review the shorter duplicate before removing it.",
  "",
  "| File | Match | Action |",
  "| :--- | ---: | :---: |",
  "| Fitchett2014.pdf | 78% | Keep |",
  "| IDC2020.pdf | 78% | Review |",
  "",
  "See the [collection guide](https://example.com/collections) for the grouping criteria.",
  "",
  "```json",
  "{",
  '  "collection": "Research methods",',
  '  "duplicates": 2',
  "}",
  "```",
].join("\n")

export const chatSessionSections: readonly ChatSessionSection[] = [
  {
    id: "today",
    title: "Today",
    rows: [
      { id: "s1", title: "Review collection PDFs", detail: "12 messages" },
      { id: "s2", title: "Summarize research notes", detail: "4 messages" },
    ],
  },
  {
    id: "yesterday",
    title: "Yesterday",
    rows: [
      { id: "s3", title: "Group duplicates by theme", detail: "7 messages" },
      { id: "s4", title: "Find citation gaps", detail: "2 messages" },
    ],
  },
  {
    id: "last-week",
    title: "Previous 7 Days",
    rows: [
      { id: "s5", title: "Organize downloads folder", detail: "9 messages" },
      { id: "s6", title: "Tag unread papers", detail: "3 messages" },
    ],
  },
]

export const chatTranscriptMessages: readonly ChatMessage[] = [
  {
    id: "m1",
    role: "user",
    content: "Summarize the selected research PDFs and group recurring file organization themes.",
    timestamp: { label: "10:24" },
  },
  {
    id: "m2",
    role: "assistant",
    content: chatRichMarkdownContent,
    timestamp: { label: "10:24" },
  },
  {
    id: "m3",
    role: "user",
    content: "Yes, create a collection for each theme.",
    timestamp: { label: "10:25" },
  },
  {
    id: "m4",
    role: "user",
    content: "Also surface likely duplicates across the citation group.",
    timestamp: { label: "10:25", isTimestampVisuallySuppressed: true },
  },
  {
    id: "m5",
    role: "assistant",
    content:
      "Created three collections. Two likely duplicates found in the citation group: IDC2020 and Fitchett2014 share 78% referenced works. I kept the longer survey and flagged the other.",
    timestamp: { label: "10:26" },
  },
  {
    id: "m6",
    role: "system",
    content: "System context: selected research PDFs are available for analysis.",
    timestamp: { label: "10:26" },
  },
  {
    id: "m7",
    role: "tool",
    content: "Tool result: grouped 6 PDFs into 3 recurring themes.",
    timestamp: { label: "10:26" },
  },
]

export const chatStreamingAssistant: ChatStreamingAssistant = {
  title: "Assistant",
  thinkingLabel: "Thinking",
  activityStatusLabel: "Reading 6 PDFs",
}

export const chatStreamingFailure: ChatStreamingAssistant = {
  title: "Assistant",
  content:
    "I reviewed 6 PDFs. Three themes recur: citation networks around Fitchett 2014 and file-organization",
  failure: {
    message: "Connection lost while generating the response.",
  },
}

export const chatConnectionError: ChatConnectionError = {
  title: "Connect an AI provider",
  detail: "Set up a provider in Settings to chat with this context.",
  actionLabel: "Open Settings",
}

// 원본: AiChatDisplayModels.swift aiChatExecutionFailureMetadata ("Chat unavailable" / "Retry").
export const chatProviderFailure: ChatConnectionError = {
  title: "Chat unavailable",
  detail: "The last request failed before completing. Retry to continue.",
  actionLabel: "Retry",
}

export const chatSurfaceHistory: ChatSurfaceState = {
  kind: "sessions",
  sections: chatSessionSections,
}

export const chatSurfaceConversation: ChatSurfaceState = {
  kind: "transcript",
  messages: chatTranscriptMessages,
  inputBar: aiChatInputReadyEmpty,
  canRegenerate: true,
}

export const chatSurfaceStreaming: ChatSurfaceState = {
  kind: "transcript",
  messages: chatTranscriptMessages.slice(0, 1),
  inputBar: aiChatInputProcessing,
  streamingAssistant: chatStreamingAssistant,
  isProcessing: true,
}

export const chatSurfaceError: ChatSurfaceState = {
  kind: "transcript",
  messages: chatTranscriptMessages.slice(0, 3),
  inputBar: aiChatInputReadyEmpty,
  streamingAssistant: chatStreamingFailure,
  canRegenerate: true,
}

// 원본: FileManagerAiChatPageView.swift AiChatEmptyStateContent ("Ask Voyager").
export const chatSurfaceEmpty: ChatSurfaceState = {
  kind: "centeredEmpty",
  emptyTitle: "Ask Voyager",
  emptyDetail: "Explore your files, collections, and ideas with Voyager.",
  inputBar: aiChatInputReadyEmpty,
}

// content page unconnected empty — centered content + compactConnectionCTA.
export const chatSurfaceCenteredUnconnected: ChatSurfaceState = {
  kind: "centeredEmpty",
  emptyTitle: "Ask Voyager",
  emptyDetail: "Explore your files, collections, and ideas with Voyager.",
  inputBar: aiChatInputUnconnected,
  connectionError: chatConnectionError,
}

// inspector connected empty — surface .empty는 본문 없이 composer만 (EmptyView).
export const chatSurfaceInspectorEmpty: ChatSurfaceState = {
  kind: "transcript",
  messages: [],
  inputBar: aiChatInputReadyEmpty,
}

export const chatSurfaceUnconnected: ChatSurfaceState = {
  kind: "unconnected",
  inputBar: aiChatInputUnconnected,
  connectionError: chatConnectionError,
}

// inspector surface-level error — status banner + errorRecovery 액션.
export const chatSurfaceConnectionError: ChatSurfaceState = {
  kind: "connectionError",
  inputBar: aiChatInputReadyEmpty,
  connectionError: chatProviderFailure,
}

// sessionStatus == .rebindRequired — rebind 배너 + 기존 transcript.
export const chatSurfaceRebind: ChatSurfaceState = {
  kind: "transcript",
  messages: chatTranscriptMessages,
  inputBar: aiChatInputReadyEmpty,
  canRegenerate: true,
  rebindRequired: true,
}
