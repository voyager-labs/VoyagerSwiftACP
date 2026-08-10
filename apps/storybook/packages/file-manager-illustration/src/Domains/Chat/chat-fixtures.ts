import type {
  ChatConnectionError,
  ChatMessage,
  ChatSessionSection,
  ChatStreamingAssistant,
  ChatSurfaceState,
} from "../../model/types"
import { aiChatInputProcessing, aiChatInputReadyEmpty } from "./ai-chat-input-fixtures"

// 채팅 도메인 deterministic fixture — network·clock·random 미의존.
// 원본: AiChatState (sessionList, transcriptHistory, streamingAssistantDisplayModel).

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
    timestamp: "10:24",
  },
  {
    id: "m2",
    role: "assistant",
    content:
      "I reviewed 6 PDFs. Three themes recur: citation networks around Fitchett 2014, file-organization taxonomies, and usability evaluation methods. Want me to create a collection for each theme?",
    timestamp: "10:24",
  },
  {
    id: "m3",
    role: "user",
    content: "Yes, and surface likely duplicates across the citation group.",
    timestamp: "10:25",
  },
  {
    id: "m4",
    role: "assistant",
    content:
      "Created three collections. Two likely duplicates found in the citation group: IDC2020 and Fitchett2014 share 78% referenced works. I kept the longer survey and flagged the other.",
    timestamp: "10:26",
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
    message: "Connection lost while generating the response. Retry to continue.",
    recoveryLabel: "Retry",
  },
}

export const chatConnectionError: ChatConnectionError = {
  title: "Connect an AI provider",
  detail: "Add an API key in Settings to start chatting with Voyager about your files.",
  actionLabel: "Open Settings",
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

export const chatSurfaceEmpty: ChatSurfaceState = {
  kind: "centeredEmpty",
  emptyTitle: "Ask about your files",
  emptyDetail: "Voyager can summarize, organize, and find connections across the selected entries.",
  inputBar: aiChatInputReadyEmpty,
  connectionError: chatConnectionError,
}
