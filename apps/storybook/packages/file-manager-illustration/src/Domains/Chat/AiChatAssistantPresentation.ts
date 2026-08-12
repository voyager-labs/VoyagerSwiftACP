import type { ChatFailure } from "../../model/types"

export type AiChatAssistantHeaderPresentation = {
  readonly title: string
  readonly thinkingLabel?: string
  readonly activityStatusLabel?: string
}

type CompletedAssistantPresentation =
  | {
      readonly kind: "completed"
      readonly content: string
      readonly failure?: ChatFailure
      readonly header?: never
    }
  | {
      readonly kind: "completed"
      readonly content?: never
      readonly failure: ChatFailure
      readonly header?: never
    }
  | {
      readonly kind: "completed"
      readonly content?: never
      readonly failure?: never
      readonly header: AiChatAssistantHeaderPresentation
    }
  | {
      readonly kind: "completed"
      readonly content?: never
      readonly failure?: never
      readonly header?: never
    }

export type AiChatAssistantPresentation =
  | {
      readonly kind: "waiting"
      readonly header: AiChatAssistantHeaderPresentation
    }
  | {
      readonly kind: "streaming"
      readonly content: string
    }
  | {
      readonly kind: "partial-failure"
      readonly content: string
      readonly failure: ChatFailure
    }
  | {
      readonly kind: "terminal-failure"
      readonly failure: ChatFailure
    }
  | CompletedAssistantPresentation

export type AiChatAssistantPresentationSource = {
  readonly title: string
  readonly thinkingLabel?: string | undefined
  readonly activityStatusLabel?: string | undefined
  readonly content?: string | undefined
  readonly isProcessing?: boolean | undefined
  readonly failure?: string | ChatFailure | undefined
  readonly headerPresentation?: "full" | "completedHistorical" | undefined
}

export function resolveAiChatAssistantPresentation(
  source: AiChatAssistantPresentationSource,
): AiChatAssistantPresentation {
  const content = nonEmpty(source.content)
  const failure = normalizeFailure(source.failure)

  if (source.headerPresentation === "completedHistorical") {
    if (content != null) {
      return failure == null
        ? { kind: "completed", content }
        : { kind: "completed", content, failure }
    }
    return failure == null ? { kind: "completed" } : { kind: "completed", failure }
  }

  if (failure != null) {
    return content == null
      ? { kind: "terminal-failure", failure }
      : { kind: "partial-failure", content, failure }
  }

  if (source.isProcessing === true) {
    return content == null
      ? { kind: "waiting", header: makeHeader(source) }
      : { kind: "streaming", content }
  }

  return content == null
    ? { kind: "completed", header: makeHeader(source) }
    : { kind: "completed", content }
}

function makeHeader(source: AiChatAssistantPresentationSource): AiChatAssistantHeaderPresentation {
  return {
    title: source.title,
    ...(source.thinkingLabel == null || source.thinkingLabel === ""
      ? {}
      : { thinkingLabel: source.thinkingLabel }),
    ...(source.activityStatusLabel == null || source.activityStatusLabel === ""
      ? {}
      : { activityStatusLabel: source.activityStatusLabel }),
  }
}

function normalizeFailure(value: string | ChatFailure | undefined): ChatFailure | undefined {
  if (value == null) return undefined

  if (typeof value === "string") {
    const message = nonEmpty(value)
    return message == null ? undefined : { message }
  }

  const message = nonEmpty(value.message)
  return message == null
    ? undefined
    : {
        message,
        ...(value.recoveryLabel == null || value.recoveryLabel.trim() === ""
          ? {}
          : { recoveryLabel: value.recoveryLabel }),
      }
}

function nonEmpty(value: string | undefined): string | undefined {
  return value == null || value.trim() === "" ? undefined : value
}
