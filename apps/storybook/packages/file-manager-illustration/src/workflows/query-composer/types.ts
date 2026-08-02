export type ComposerPhase =
  | "idle"
  | "draft"
  | "searching"
  | "chipsAppliedPendingList"
  | "listApplied"
  | "failed"

export type ComposerScopeMode = "rootOnly" | "singleExplicit" | "multiExplicit" | "exceptions"

export type ComposerFeedbackKind = "info" | "error" | "delayed"

export type ComposerCondition = {
  readonly id: string
  readonly property: string
  readonly operator: string
  readonly value: string
}

export type ComposerScope = {
  readonly mode: ComposerScopeMode
  readonly primary: string
  readonly secondary: string
  readonly exceptions?: string
}

export type ComposerFeedback = {
  readonly kind: ComposerFeedbackKind
  readonly message: string
}

export type ComposerDraft = {
  readonly text: string
  readonly phase: ComposerPhase
  readonly scope: ComposerScope
  readonly conditions: readonly ComposerCondition[]
  readonly feedback?: ComposerFeedback
  readonly canUndo?: boolean
  readonly canRedo?: boolean
  readonly includeDirectories?: boolean
  readonly includeSubfolders?: boolean
  readonly collectionMode?: boolean
}
