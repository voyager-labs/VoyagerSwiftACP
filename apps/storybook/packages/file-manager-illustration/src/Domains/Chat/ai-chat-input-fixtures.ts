import type { AiChatInputBarPresentation } from "../../model/types"

const defaultModelSelector = {
  label: "GPT-5.2",
  accessibilityLabel: "Model",
  accessibilityValue: "GPT-5.2",
  isDisabled: false,
  value: "gpt-5.2",
  options: [{ value: "gpt-5.2", label: "GPT-5.2", detail: "OpenAI" }],
} as const

const defaultThinkingSelector = {
  label: "Medium",
  accessibilityLabel: "Thinking",
  accessibilityValue: "Medium",
  isDisabled: false,
  value: "medium",
  options: [
    { value: "low", label: "Low" },
    { value: "medium", label: "Medium" },
    { value: "high", label: "High" },
  ],
} as const

export const aiChatInputReadyEmpty = {
  placeholder: "Ask anything…",
  inputAccessibilityLabel: "Chat message",
  inputAccessibilityHint: "Enter to send, Shift+Enter for new line",
  contextAffordanceLabel: "Add attachment",
  modelSelector: defaultModelSelector,
  thinkingSelector: defaultThinkingSelector,
  action: {
    kind: "submit",
    isEnabled: false,
    accessibilityLabel: "Send",
    help: "Enter to send, Shift+Enter for new line",
  },
  isComposerEditingDisabled: false,
  contextSections: [],
} satisfies AiChatInputBarPresentation

export const aiChatInputReadyDraft = {
  ...aiChatInputReadyEmpty,
  action: {
    ...aiChatInputReadyEmpty.action,
    isEnabled: true,
  },
} satisfies AiChatInputBarPresentation

export const aiChatInputPendingResolution = {
  ...aiChatInputReadyEmpty,
  modelSelector: { ...defaultModelSelector, isDisabled: true },
  thinkingSelector: { ...defaultThinkingSelector, isDisabled: true },
  action: {
    kind: "stop",
    isEnabled: true,
    accessibilityLabel: "Stop",
    help: "Stop generating response",
  },
  isComposerEditingDisabled: true,
} satisfies AiChatInputBarPresentation

export const aiChatInputProcessing = {
  ...aiChatInputReadyEmpty,
  action: {
    kind: "stop",
    isEnabled: true,
    accessibilityLabel: "Stop",
    help: "Stop generating response",
  },
} satisfies AiChatInputBarPresentation

export const aiChatInputProcessingStopDisabled = {
  ...aiChatInputProcessing,
  action: {
    ...aiChatInputProcessing.action,
    isEnabled: false,
  },
} satisfies AiChatInputBarPresentation

export const aiChatInputModelUnavailable = {
  ...aiChatInputReadyEmpty,
  modelSelector: {
    label: "Unavailable",
    accessibilityLabel: "Model",
    accessibilityValue: "Unavailable",
    isDisabled: true,
    value: "unavailable",
    options: [{ value: "unavailable", label: "Unavailable", disabled: true }],
  },
  thinkingSelector: {
    label: "Unavailable",
    accessibilityLabel: "Thinking",
    accessibilityValue: "Unavailable",
    isDisabled: true,
    value: "unavailable",
    options: [{ value: "unavailable", label: "Unavailable", disabled: true }],
  },
} satisfies AiChatInputBarPresentation

export const aiChatInputWithContext = {
  ...aiChatInputReadyDraft,
  contextSections: [
    {
      id: "current-response",
      kind: "currentResponse",
      label: "Current response context",
      isEditable: false,
      groups: [
        {
          id: "current-context",
          label: "Current context",
          items: [
            {
              id: "locked-research",
              title: "Research PDFs",
              detail: "6 selected entries · OpenAI",
              symbolName: "folder.fill",
            },
          ],
        },
      ],
    },
    {
      id: "next-message",
      kind: "nextMessage",
      label: "Next message context",
      isEditable: true,
      groups: [
        {
          id: "attachments",
          label: "Attachments",
          items: [
            {
              id: "fitchett-2014",
              title: "Fitchett2014.pdf",
              detail: "PDF · OpenAI",
              symbolName: "doc.text",
              isRemovable: true,
            },
            {
              id: "idc-2020",
              title: "IDC2020.pdf",
              detail: "PDF · OpenAI",
              symbolName: "doc.text",
              isRemovable: true,
            },
          ],
        },
      ],
    },
  ],
} satisfies AiChatInputBarPresentation
